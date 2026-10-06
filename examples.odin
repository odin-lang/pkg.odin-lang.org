package odin_html_docs

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:io"
import "core:log"
import "core:os"
import "core:path/slashpath"
import "core:slice"
import "core:strings"

import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import doc "core:odin/doc-format"

import be "bundle_examples"

// The programs of odin-lang/examples, from the bundle `bundle_examples` makes, and where they use what's documented

examples: be.Examples_Bundle

Example_Use :: struct {
	program, file: int,
	line:          int,
	from, to:      int, // the lines an excerpt shows: the procedure around the use, or the part of it near the use
}

// Excerpts longer than this show only the lines near the use
EXAMPLE_EXCERPT_MAX_LINES :: 24
EXAMPLES_SHOWN :: 3

example_uses:  map[^doc.Pkg]map[string][dynamic]Example_Use
example_links: [][]map[int]string // by program and file: where a name starts, and the page of what it names
example_lines: [][][]string       // by program and file: each line, highlighted, once needed

load_examples :: proc(path: string) -> bool {
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {
		log.warnf("unable to read the examples bundle %s: %v", path, err)
		return false
	}
	if json_err := json.unmarshal(data, &examples); json_err != nil {
		log.warnf("unable to read the examples bundle %s: %v", path, json_err)
		return false
	}
	if examples.format != be.FORMAT_VERSION {
		log.warnf("the examples bundle %s is in format %d, rather than %d; make it again with bundle_examples", path, examples.format, be.FORMAT_VERSION)
		examples = {}
		return false
	}
	return true
}

index_examples :: proc() {
	context.allocator = runtime.default_allocator()
	example_links = make([][]map[int]string, len(examples.programs))
	example_lines = make([][][]string, len(examples.programs))
	for program, pi in examples.programs {
		example_links[pi] = make([]map[int]string, len(program.files))
		example_lines[pi] = make([][]string, len(program.files))
		for _, fi in program.files {
			index_example_file(pi, fi)
		}
	}
}

@(private="file")
index_example_file :: proc(pi, fi: int) {
	file := examples.programs[pi].files[fi]
	p := parser.default_parser()
	p.err  = proc(pos: tokenizer.Pos, msg: string, args: ..any) {}
	p.warn = proc(pos: tokenizer.Pos, msg: string, args: ..any) {}
	ast_file := new(ast.File)
	ast_file^ = {src = file.source, fullpath = file.name}
	if !parser.parse_file(&p, ast_file) {
		log.warnf("examples: %s/%s doesn't parse, so isn't linked to", examples.programs[pi].path, file.name)
		return
	}

	Index :: struct {
		pi, fi:   int,
		lines:    int,
		packages: map[string]^doc.Pkg, // by the name the file imports it as
		procs:    [dynamic][2]int,     // the lines of each procedure declared at file scope
	}
	index := Index{pi = pi, fi = fi, lines = strings.count(file.source, "\n") + 1}
	for decl in ast_file.decls {
		if decl == nil {
			continue
		}
		#partial switch d in decl.derived {
		case ^ast.Import_Decl:
			path := strings.trim(d.relpath.text, "\"`")
			_, colon, rest := strings.partition(path, ":")
			if colon == "" {
				continue // the program's own packages
			}
			name := d.name.text if d.name.text != "" else slashpath.base(rest)
			if pkg := lookup_doc_pkg(path, nil); pkg != nil {
				index.packages[name] = pkg
			}
		case ^ast.Value_Decl:
			for value in d.values {
				if value != nil {
					if _, ok := value.derived.(^ast.Proc_Lit); ok {
						append(&index.procs, [2]int{d.pos.line, d.end.line})
					}
				}
			}
		}
	}
	if len(index.packages) == 0 {
		return
	}

	visitor := ast.Visitor{
		data  = &index,
		visit = proc(v: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
			if node == nil {
				return nil
			}
			selector, is_selector := node.derived.(^ast.Selector_Expr)
			if !is_selector || selector.expr == nil || selector.field == nil {
				return v
			}
			index := (^Index)(v.data)
			ident, is_ident := selector.expr.derived.(^ast.Ident)
			if !is_ident {
				return v
			}
			pkg, imported := index.packages[ident.name]
			if !imported {
				return v
			}
			name := selector.field.name
			if name not_in cfg.pkg_link_names[pkg] {
				return v
			}

			links := &example_links[index.pi][index.fi]
			links[selector.field.pos.offset] = strings.clone(doc_entity_url(pkg, name))
			if !is_about(examples.programs[index.pi], pkg) {
				return v
			}

			line := selector.field.pos.line
			use := Example_Use{program = index.pi, file = index.fi, line = line, from = max(1, line-3), to = min(index.lines, line+3)}
			for r in index.procs {
				if r[0] <= line && line <= r[1] {
					if r[1] - r[0] + 1 <= EXAMPLE_EXCERPT_MAX_LINES {
						use.from, use.to = r[0], r[1]
					} else {
						use.from, use.to = max(r[0], line-5), min(r[1], line+5)
					}
					break
				}
			}
			by_name := example_uses[pkg]
			uses := by_name[name]
			append(&uses, use)
			by_name[name] = uses
			example_uses[pkg] = by_name
			return v
		},
	}
	for decl in ast_file.decls {
		if decl != nil {
			ast.walk(&visitor, decl)
		}
	}
}

@(private="file")
is_about :: proc(program: be.Example_Program, pkg: ^doc.Pkg) -> bool {
	// in a folder named after it, e.g. `nbio/tcp-echo` for `core:nbio`, or one the config names for it
	collection := cfg.pkg_to_collection[pkg]
	dir := strings.to_lower(slashpath.base(collection.pkg_to_path[pkg]), context.temp_allocator)
	for part in strings.split(strings.to_lower(program.path, context.temp_allocator), "/", context.temp_allocator) {
		if part == dir {
			return true
		}
	}
	for folder in cfg.example_folders[pkg_import_path(pkg)] or_else nil {
		if program.path == folder || strings.has_prefix(program.path, folder) && strings.has_prefix(program.path[len(folder):], "/") {
			return true
		}
	}
	return false
}

ranked_example_uses :: proc(pkg: ^doc.Pkg, name: string) -> []Example_Use {
	// one use in each program, the shortest excerpt of it, any whose code can be shown first
	uses := (example_uses[pkg] or_else nil)[name] or_else nil
	if len(uses) == 0 {
		return nil
	}
	best := make(map[int]Example_Use, len(uses), context.temp_allocator)
	for use in uses {
		if prev, ok := best[use.program]; !ok || use.to - use.from < prev.to - prev.from {
			best[use.program] = use
		}
	}
	ranked := make([dynamic]Example_Use, 0, len(best), context.temp_allocator)
	for _, use in best {
		append(&ranked, use)
	}
	slice.sort_by(ranked[:], proc(a, b: Example_Use) -> bool {
		pa, pb := examples.programs[a.program], examples.programs[b.program]
		// what the folded line names is what opening it shows
		if pa.link_only != pb.link_only {
			return !pa.link_only
		}
		if a.to - a.from != b.to - b.from {
			return a.to - a.from < b.to - b.from
		}
		return pa.path < pb.path
	})
	return ranked[:]
}

write_entry_examples :: proc(w: io.Writer, pkg: ^doc.Pkg, name: string) {
	ranked := ranked_example_uses(pkg, name)
	if len(ranked) == 0 {
		return
	}
	fmt.wprintf(w, `<details class="doc-examples" data-name="%s"><summary>External examples <span class="doc-examples-names">`, name)
	for use, i in ranked[:min(len(ranked), EXAMPLES_SHOWN)] {
		if i > 0 {
			io.write_string(w, " · ")
		}
		io.write_string(w, escape_html_string(examples.programs[use.program].path, context.temp_allocator))
	}
	if len(ranked) > EXAMPLES_SHOWN {
		fmt.wprintf(w, " +%d", len(ranked) - EXAMPLES_SHOWN)
	}
	io.write_string(w, "</span></summary><div class=\"doc-examples-body\"></div></details>\n")
}

write_pkg_examples :: proc(w: io.Writer, pkg: ^doc.Pkg) -> (count: int) {
	by_name := example_uses[pkg] or_else nil
	if len(by_name) == 0 {
		return
	}
	// how many of the package's declarations each program uses
	used := make(map[int]int, 16, context.temp_allocator)
	for _, uses in by_name {
		seen := make(map[int]bool, 4, context.temp_allocator)
		for use in uses {
			if !seen[use.program] {
				seen[use.program] = true
				used[use.program] += 1
			}
		}
	}

	// the folders the programs are in, as the repo has them
	Node :: struct {
		name:     string,
		program:  int, // -1 for a folder that isn't a program itself
		children: [dynamic]^Node,
		programs: int, // in it and under it
	}
	new_node :: proc(name: string) -> ^Node {
		node := new(Node, context.temp_allocator)
		node^ = {name = name, program = -1, children = make([dynamic]^Node, context.temp_allocator)}
		return node
	}
	root := new_node("")
	for index in used {
		node := root
		node.programs += 1
		for part in strings.split(examples.programs[index].path, "/", context.temp_allocator) {
			child: ^Node
			for c in node.children {
				if c.name == part {
					child = c
					break
				}
			}
			if child == nil {
				child = new_node(part)
				append(&node.children, child)
			}
			node = child
			node.programs += 1
		}
		node.program = index
	}

	write_node :: proc(w: io.Writer, node: ^Node, used: map[int]int) {
		slice.sort_by(node.children[:], proc(a, b: ^Node) -> bool {
			return strings.to_lower(a.name, context.temp_allocator) < strings.to_lower(b.name, context.temp_allocator)
		})
		for child in node.children {
			// a folder holding only a folder is one label, e.g. `learn_opengl/1_getting_started/`
			label := child.name
			n := child
			for n.program < 0 && len(n.children) == 1 && n.children[0].program < 0 {
				n = n.children[0]
				label = fmt.tprintf("%s/%s", label, n.name)
			}
			io.write_string(w, "<li>")
			if n.program >= 0 {
				program := examples.programs[n.program]
				fmt.wprintf(w, `<a href="%s/tree/%s/%s"`, examples.repo, examples.commit, program.path)
				if summary := doc_summary(program.readme); summary != "" {
					fmt.wprintf(w, ` title="%s"`, escape_html_string(summary, context.temp_allocator))
				}
				fmt.wprintf(w, `>%s</a><span class="pkg-examples-used" title="uses %d of the package's declarations">%d</span>`, label, used[n.program], used[n.program])
			} else {
				fmt.wprintf(w, `<span class="pkg-examples-folder">%s/</span>`, label)
			}
			if len(n.children) > 0 {
				io.write_string(w, "<ul>")
				write_node(w, n, used)
				io.write_string(w, "</ul>")
			}
			io.write_string(w, "</li>\n")
		}
	}

	tree := strings.builder_make(context.temp_allocator)
	write_node(strings.to_writer(&tree), root, used)

	// a long tree is its top folders side by side, each whole, rather than a page of one column
	LINES_FOR_COLUMNS :: 30
	columns := strings.count(strings.to_string(tree), "<li>") > LINES_FOR_COLUMNS

	fmt.wprintf(w, `<h2 id="pkg-external-examples"><a class="pkg-section-link" href="#pkg-external-examples">External Examples <span class="pkg-count">%d</span><span class="a-hidden">&nbsp;¶</span></a></h2>`+"\n", len(used))
	fmt.wprintf(w, `<p class="pkg-examples-note">The programs in <a href="%s">odin-lang/examples</a> about this package, and how many of its declarations each uses.</p>`+"\n", examples.repo)
	fmt.wprintf(w, `<ul class="pkg-examples-tree%s">`, " pkg-examples-columns" if columns else "")
	io.write_string(w, strings.to_string(tree))
	io.write_string(w, "</ul>\n")
	return len(used)
}

write_examples_json :: proc(w: io.Writer, pkg: ^doc.Pkg) -> bool {
	// loaded when a declaration's examples are first opened
	by_name := example_uses[pkg] or_else nil
	if len(by_name) == 0 {
		return false
	}
	names := make([dynamic]string, 0, len(by_name), context.temp_allocator)
	for name in by_name {
		append(&names, name)
	}
	slice.sort(names[:])

	io.write_string(w, `{"repo": `)
	write_json_string(w, examples.repo)
	io.write_string(w, `, "commit": `)
	write_json_string(w, examples.commit)
	io.write_string(w, `, "decls": {`)
	for name, i in names {
		if i > 0 {
			io.write_string(w, ",")
		}
		io.write_string(w, "\n")
		write_json_string(w, name)
		io.write_string(w, ": [")
		shown := 0
		for use, j in ranked_example_uses(pkg, name) {
			program := examples.programs[use.program]
			if j > 0 {
				io.write_string(w, ", ")
			}
			fmt.wprintf(w, `{{"p": %q, "f": %q, "l": %d, "from": %d, "to": %d`, program.path, program.files[use.file].name, use.line, use.from, use.to)
			if !program.link_only && shown < EXAMPLES_SHOWN {
				shown += 1
				io.write_string(w, `, "html": `)
				write_json_string(w, example_excerpt(use))
			}
			if program.license.path != "" {
				io.write_string(w, `, "license": `)
				write_json_string(w, license_line(program.license.text))
				io.write_string(w, `, "license_path": `)
				write_json_string(w, program.license.path)
			}
			io.write_string(w, "}")
		}
		io.write_string(w, "]")
	}
	io.write_string(w, "\n}}\n")
	return true
}

@(private="file")
license_line :: proc(text: string) -> string {
	// "LearnOpenGL.com © 2025 by Joey de Vries is licensed under CC BY-NC 4.0…", for a short note
	text := text
	for line in strings.split_lines_iterator(&text) {
		if t := strings.trim_space(line); t != "" {
			return t if len(t) <= 100 else fmt.tprintf("%s…", t[:100])
		}
	}
	return "its own licence"
}

@(private="file")
example_excerpt :: proc(use: Example_Use) -> string {
	lines := example_html_lines(use.program, use.file)
	b := strings.builder_make(context.temp_allocator)
	for n in use.from..=use.to {
		if n < 1 || n > len(lines) {
			continue
		}
		hit := n == use.line
		if hit {
			strings.write_string(&b, `<span class="doc-example-hit">`)
		}
		fmt.sbprintf(&b, `<span class="ln">%d</span>%s`, n, lines[n-1])
		if hit {
			strings.write_string(&b, "</span>")
		}
		strings.write_byte(&b, '\n')
	}
	return strings.to_string(b)
}

example_html_lines :: proc(pi, fi: int) -> []string {
	if example_lines[pi][fi] == nil {
		example_lines[pi][fi] = highlight_example(examples.programs[pi].files[fi].source, example_links[pi][fi])
	}
	return example_lines[pi][fi]
}

@(private="file")
highlight_example :: proc(src: string, links: map[int]string) -> []string {
	// classed as highlight.js classes them, so they look as the docs' own examples do; the names in `links` link to their docs
	context.allocator = runtime.default_allocator()

	Lines :: struct {
		lines: [dynamic]string,
		b:     strings.Builder,
	}
	out := Lines{b = strings.builder_make()}
	defer strings.builder_destroy(&out.b)

	write :: proc(out: ^Lines, text: string, class := "", url := "") {
		rest := text
		for {
			nl := strings.index_byte(rest, '\n')
			piece := rest if nl < 0 else rest[:nl]
			if piece != "" {
				switch {
				case url != "":   fmt.sbprintf(&out.b, `<a href="%s">`, url)
				case class != "": fmt.sbprintf(&out.b, `<span class="%s">`, class)
				}
				strings.write_string(&out.b, escape_html_string(piece, context.temp_allocator))
				switch {
				case url != "":   strings.write_string(&out.b, "</a>")
				case class != "": strings.write_string(&out.b, "</span>")
				}
			}
			if nl < 0 {
				return
			}
			append(&out.lines, strings.clone(strings.to_string(out.b)))
			strings.builder_reset(&out.b)
			rest = rest[nl+1:]
		}
	}

	t: tokenizer.Tokenizer
	tokenizer.init(&t, src, "example.odin", proc(pos: tokenizer.Pos, msg: string, args: ..any) {})
	last := 0
	directive := false
	for {
		tok := tokenizer.scan(&t)
		if tok.kind == .EOF {
			break
		}
		start := tok.pos.offset
		end := start + len(tok.text)
		if start < last || end > len(src) || src[start:end] != tok.text {
			continue
		}
		write(&out, src[last:start])

		class, url := "", ""
		#partial switch tok.kind {
		case .Comment:
			class = "hljs-comment"
		case .String, .Rune:
			class = "hljs-string"
		case .Integer, .Float, .Imag:
			class = "hljs-number"
		case .Hash, .At:
			class = "hljs-meta"
			directive = tok.kind == .Hash
		case .Ident:
			switch {
			case directive:
				class = "hljs-meta"
			case start in links:
				url = links[start]
			case:
				class = builtin_class(tok.text)
			}
		case:
			if .B_Keyword_Begin < tok.kind && tok.kind < .B_Keyword_End {
				class = "hljs-keyword"
			}
		}
		if tok.kind != .Hash {
			directive = false
		}
		write(&out, src[start:end], class, url)
		last = end
	}
	write(&out, src[last:])
	if strings.builder_len(out.b) > 0 {
		append(&out.lines, strings.clone(strings.to_string(out.b)))
	}
	return out.lines[:]
}

@(private="file")
builtin_class :: proc(name: string) -> string {
	switch name {
	case "true", "false", "nil":
		return "hljs-literal"
	case "bool", "b8", "b16", "b32", "b64", "int", "i8", "i16", "i32", "i64", "i128", "uint", "u8", "u16", "u32", "u64", "u128",
	     "uintptr", "f16", "f32", "f64", "complex32", "complex64", "complex128", "quaternion64", "quaternion128", "quaternion256",
	     "rune", "string", "cstring", "rawptr", "typeid", "any", "byte":
		return "hljs-type"
	case "len", "cap", "size_of", "align_of", "offset_of", "type_of", "type_info_of", "typeid_of", "make", "new", "free", "delete",
	     "append", "clear", "copy", "min", "max", "abs", "clamp", "panic", "assert", "unreachable", "resize", "reserve", "raw_data",
	     "inject_at", "ordered_remove", "unordered_remove", "pop", "free_all", "new_clone", "swizzle":
		return "hljs-built_in"
	}
	return ""
}
