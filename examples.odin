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
example_links: [][]map[int]string       // by program and file: where a name starts, and the page of what it names
example_lines: [][][]string             // by program and file: each line, highlighted, once needed
example_files: [][]Example_File_Info    // by program and file

Example_File_Info :: struct {
	main:     bool,                  // it declares `main`
	build:    string,                // its `#+build` constraint, e.g. "windows" or "!js"
	procs:    [dynamic]Example_Proc, // declared at file scope
	packages: [dynamic]^doc.Pkg,     // the documented packages it imports
	used:     [dynamic]Example_Name, // the documented declarations it names, as often as it does
}

Example_Proc :: struct {
	name: string,
	line: int,
}

Example_Name :: struct {
	pkg:  ^doc.Pkg,
	name: string,
}

// Each program is a page, except that a folder of programs that are each a file, like `raylib/ports/core`,
// is a page for each of those files as well as one for the folder
Example_Page :: struct {
	path:    string,       // in the repo, and on the site under EXAMPLES_URL
	program: int,
	file:    int,          // the file it is, or -1 for the program
	members: [dynamic]int, // the pages of its files that are programs
}

EXAMPLES_URL :: "/examples"

example_pages:   [dynamic]Example_Page
example_page_of: [][]int        // by program and file: the page showing it
example_page_at: map[string]int // by path

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
	example_files = make([][]Example_File_Info, len(examples.programs))
	for program, pi in examples.programs {
		example_links[pi] = make([]map[int]string, len(program.files))
		example_lines[pi] = make([][]string, len(program.files))
		example_files[pi] = make([]Example_File_Info, len(program.files))
		for _, fi in program.files {
			index_example_file(pi, fi)
		}
	}

	example_page_of = make([][]int, len(examples.programs))
	for program, pi in examples.programs {
		example_page_at[program.path] = len(example_pages)
		example_page_of[pi] = make([]int, len(program.files))
		slice.fill(example_page_of[pi], len(example_pages))
		append(&example_pages, Example_Page{path = program.path, program = pi, file = -1})
	}
	for program, pi in examples.programs {
		mains := 0
		for info in example_files[pi] {
			mains += int(info.main)
		}
		if mains < 2 {
			continue
		}
		folder := example_page_at[program.path]
		for file, fi in program.files {
			path := fmt.aprintf("%s/%s", program.path, strings.trim_suffix(file.name, ".odin"))
			if !example_files[pi][fi].main || path in example_page_at {
				continue
			}
			page := len(example_pages)
			append(&example_pages, Example_Page{path = path, program = pi, file = fi})
			append(&example_pages[folder].members, page)
			example_page_at[path] = page
			example_page_of[pi][fi] = page
		}
	}
}

@(private="file")
index_example_file :: proc(pi, fi: int) {
	file := examples.programs[pi].files[fi]
	info := &example_files[pi][fi]
	info.build = build_constraint(file.source)

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
		info:     ^Example_File_Info,
		packages: map[string]^doc.Pkg, // by the name the file imports it as
		procs:    [dynamic][2]int,     // the lines of each procedure declared at file scope
	}
	index := Index{pi = pi, fi = fi, lines = strings.count(file.source, "\n") + 1, info = info}
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
				if !slice.contains(info.packages[:], pkg) {
					append(&info.packages, pkg)
				}
			}
		case ^ast.Value_Decl:
			for value, i in d.values {
				if value == nil {
					continue
				}
				if _, ok := value.derived.(^ast.Proc_Lit); ok {
					append(&index.procs, [2]int{d.pos.line, d.end.line})
					if i < len(d.names) {
						if ident, is_ident := d.names[i].derived.(^ast.Ident); is_ident {
							append(&info.procs, Example_Proc{ident.name, d.pos.line})
							if ident.name == "main" {
								info.main = true
							}
						}
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
			append(&index.info.used, Example_Name{pkg, name})
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
build_constraint :: proc(src: string) -> string {
	// `#+build windows`, or the older `//+build windows`, before the package clause
	rest := src
	for line in strings.split_lines_iterator(&rest) {
		t := strings.trim_space(line)
		if strings.has_prefix(t, "#+build ") {
			return strings.trim_space(t[len("#+build "):])
		}
		if strings.has_prefix(t, "//+build ") {
			return strings.trim_space(t[len("//+build "):])
		}
		if strings.has_prefix(t, "package ") {
			break
		}
	}
	return ""
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

example_url :: proc(page: int) -> string {
	return fmt.tprintf("%s/%s/", EXAMPLES_URL, example_pages[page].path)
}

// On GitHub at the bundle's commit: `kind` is "tree" for a folder, "blob" for a file
example_github_url :: proc(path: string, kind := "blob") -> string {
	escaped, _ := strings.replace_all(path, " ", "%20", context.temp_allocator)
	return fmt.tprintf("%s/%s/%s/%s", examples.repo, kind, examples.commit, escaped)
}

example_line_url :: proc(pi, fi, line: int) -> string {
	program := examples.programs[pi]
	name := program.files[fi].name
	if program.link_only {
		return fmt.tprintf("%s#L%d", example_github_url(fmt.tprintf("%s/%s", program.path, name)), line)
	}
	return fmt.tprintf("%s#%s-L%d", example_url(example_page_of[pi][fi]), name, line)
}

ranked_example_uses :: proc(pkg: ^doc.Pkg, name: string) -> []Example_Use {
	// one use on each page, the shortest excerpt of it, any whose code can be shown first
	uses := (example_uses[pkg] or_else nil)[name] or_else nil
	if len(uses) == 0 {
		return nil
	}
	best := make(map[int]Example_Use, len(uses), context.temp_allocator)
	for use in uses {
		page := example_page_of[use.program][use.file]
		if prev, ok := best[page]; !ok || use.to - use.from < prev.to - prev.from {
			best[page] = use
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
		return example_pages[example_page_of[a.program][a.file]].path < example_pages[example_page_of[b.program][b.file]].path
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
		io.write_string(w, escape_html_text(example_pages[example_page_of[use.program][use.file]].path))
	}
	if len(ranked) > EXAMPLES_SHOWN {
		fmt.wprintf(w, " +%d", len(ranked) - EXAMPLES_SHOWN)
	}
	io.write_string(w, "</span></summary><div class=\"doc-examples-body\"></div></details>\n")
}

// The pages under a folder, as the repo has them
Example_Node :: struct {
	name, path: string,
	page:       int, // -1 for a folder without a page
	children:   [dynamic]^Example_Node,
}

// `groups` gives a folder of programs that are each a file its page, though it isn't one of `pages`
example_tree :: proc(pages: []int, groups := false) -> ^Example_Node {
	new_node :: proc(name, path: string) -> ^Example_Node {
		node := new(Example_Node, context.temp_allocator)
		node^ = {name = name, path = path, page = -1, children = make([dynamic]^Example_Node, context.temp_allocator)}
		return node
	}
	sort_nodes :: proc(node: ^Example_Node) {
		slice.sort_by(node.children[:], proc(a, b: ^Example_Node) -> bool {
			return strings.to_lower(a.name, context.temp_allocator) < strings.to_lower(b.name, context.temp_allocator)
		})
		for child in node.children {
			sort_nodes(child)
		}
	}

	root := new_node("", "")
	for page in pages {
		node := root
		for part in strings.split(example_pages[page].path, "/", context.temp_allocator) {
			child: ^Example_Node
			for c in node.children {
				if c.name == part {
					child = c
					break
				}
			}
			if child == nil {
				child = new_node(part, part if node == root else fmt.tprintf("%s/%s", node.path, part))
				if folder, ok := example_page_at[child.path]; ok && groups && len(example_pages[folder].members) > 0 {
					child.page = folder
				}
				append(&node.children, child)
			}
			node = child
		}
		node.page = page
	}
	sort_nodes(root)
	return root
}

// A folder holding only a folder is one label, e.g. `learn_opengl/1_getting_started`
example_node_label :: proc(node: ^Example_Node) -> (label: string, last: ^Example_Node) {
	label, last = node.name, node
	for last.page < 0 && len(last.children) == 1 && last.children[0].page < 0 {
		last = last.children[0]
		label = fmt.tprintf("%s/%s", label, last.name)
	}
	return
}

write_pkg_examples :: proc(w: io.Writer, pkg: ^doc.Pkg) -> (count: int) {
	by_name := example_uses[pkg] or_else nil
	if len(by_name) == 0 {
		return
	}
	// how many of the package's declarations each page uses
	used := make(map[int]int, 16, context.temp_allocator)
	for _, uses in by_name {
		seen := make(map[int]bool, 4, context.temp_allocator)
		for use in uses {
			page := example_page_of[use.program][use.file]
			if !seen[page] {
				seen[page] = true
				used[page] += 1
			}
		}
	}
	pages := make([dynamic]int, 0, len(used), context.temp_allocator)
	for page in used {
		append(&pages, page)
	}

	write_node :: proc(w: io.Writer, node: ^Example_Node, used: map[int]int, inline := false) {
		for child in node.children {
			label, n := example_node_label(child)
			io.write_string(w, `<li class="pkg-examples-member">` if inline else "<li>")
			if n.page >= 0 {
				fmt.wprintf(w, `<a href="%s"`, example_url(n.page))
				if summary := example_summary(n.page); summary != "" {
					fmt.wprintf(w, ` title="%s"`, escape_html_text(summary))
				}
				fmt.wprintf(w, `>%s</a>`, label)
				if count, ok := used[n.page]; ok {
					fmt.wprintf(w, `<span class="pkg-examples-used" title="uses %d of the package's declarations">%d</span>`, count, count)
				}
			} else {
				fmt.wprintf(w, `<span class="pkg-examples-folder">%s/</span>`, label)
			}
			if len(n.children) > 0 {
				// a folder of programs that are each a file has them run on from one to the next, as they're alike
				members := n.page >= 0 && len(example_pages[n.page].members) > 0
				for c in n.children {
					members &&= len(c.children) == 0
				}
				io.write_string(w, `<ul class="pkg-examples-inline">` if members else "<ul>")
				write_node(w, n, used, members)
				io.write_string(w, "</ul>")
			}
			io.write_string(w, "</li>\n")
		}
	}

	tree := strings.builder_make(context.temp_allocator)
	root := example_tree(pages[:], groups = true)
	write_node(strings.to_writer(&tree), root, used)

	// a long tree is its top folders side by side, each whole, rather than a page of one column
	LINES_FOR_COLUMNS :: 30
	columns := len(root.children) > 1 && strings.count(strings.to_string(tree), "<li>") > LINES_FOR_COLUMNS

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
			page := example_page_of[use.program][use.file]
			if j > 0 {
				io.write_string(w, ", ")
			}
			fmt.wprintf(w, `{{"p": %q, "u": %q, "f": %q, "l": %d, "at": %q, "from": %d, "to": %d`,
			            example_pages[page].path, example_url(page), program.files[use.file].name, use.line,
			            example_line_url(use.program, use.file, use.line), use.from, use.to)
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

// For text and attributes alike
escape_html_text :: proc(s: string, allocator := context.temp_allocator) -> string {
	if strings.index_any(s, `&<>"`) < 0 {
		return s
	}
	b := strings.builder_make(allocator)
	for i in 0..<len(s) {
		switch s[i] {
		case '&': strings.write_string(&b, "&amp;")
		case '<': strings.write_string(&b, "&lt;")
		case '>': strings.write_string(&b, "&gt;")
		case '"': strings.write_string(&b, "&quot;")
		case:     strings.write_byte(&b, s[i])
		}
	}
	return strings.to_string(b)
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
				strings.write_string(&out.b, escape_html_text(piece))
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
		case .Hash, .At, .File_Tag:
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
