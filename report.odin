package odin_html_docs

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:os"
import "core:path/slashpath"
import "core:slice"
import "core:strings"

import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import doc "core:odin/doc-format"

// The documentation report at /report/: what the docs are missing or get wrong, package by package,
// for the people writing them. It isn't linked from anywhere, nor indexed.

Report_Kind :: enum u8 {
	Unresolved_Link, // `[[name]]` naming nothing
	Stale_Name,      // `pkg.name` in backticks, where the package has no `name`
	Unknown_Param,   // Inputs or Returns names something the signature doesn't have
	Missing_Param,   // Inputs or Returns leaves out something the signature has
	Bad_Example,     // an Example that doesn't parse
	Output_Only,     // an Output without an Example
	Deprecated_Bare,     // `@(deprecated)` without saying what to use instead
	Deprecated_Unmarked, // docs calling it deprecated, without `@(deprecated)`
	Other_Name,          // docs beginning with another declaration's name, as if copied from its
	Missing_Import,      // an example using a package it doesn't import
	Misspelled,          // a word in resources/misspellings.txt, outside code
	Summary_Long,        // a first sentence too long for search results and previews
	Summary_None,        // docs beginning with something that isn't a sentence, so with no summary
	Duplicate,           // the same docs as another declaration's, as if copied and not changed
}

REPORT_KIND_CODES := [Report_Kind]string{
	.Unresolved_Link = "link",
	.Stale_Name      = "stale",
	.Unknown_Param   = "param",
	.Missing_Param   = "missing",
	.Bad_Example     = "example",
	.Output_Only     = "output",
	.Deprecated_Bare     = "deprecated",
	.Deprecated_Unmarked = "unmarked",
	.Other_Name          = "name",
	.Missing_Import      = "import",
	.Misspelled          = "spelling",
	.Summary_Long        = "summary-long",
	.Summary_None        = "summary-none",
	.Duplicate           = "duplicate",
}

Decl_Kind :: enum u8 {Type, Constant, Variable, Procedure, Proc_Group}

DECL_KIND_CODES := [Decl_Kind]string{
	.Type       = "t",
	.Constant   = "c",
	.Variable   = "v",
	.Procedure  = "p",
	.Proc_Group = "g",
}

Report_Issue :: struct {
	kind:   Report_Kind,
	name:   string,
	detail: string,
	file:   string,
	line:   int,
}

Report_Pkg :: struct {
	has_overview: bool,
	declared:     [Decl_Kind]int,
	undocumented: [Decl_Kind][dynamic]string,
	issues:       [dynamic]Report_Issue,
	// declarations by their docs, with whitespace evened out, to find the same docs twice
	by_docs:      map[string][dynamic]Docs_Owner,
}

Docs_Owner :: struct {
	entity: ^doc.Entity,
	name:   string,
	file:   string,
	line:   int,
	groups: []^doc.Entity, // the procedure groups it's a form of
}

// Shorter docs, like "Deprecated." or "See `foo`.", are alike without having been copied
DUPLICATE_MIN_LENGTH :: 50

report_pkgs: map[^doc.Pkg]^Report_Pkg

// What is being documented, while its problems belong in the report:
// a declaration on the page of the package declaring it, or the package's overview
report_pkg:    ^doc.Pkg
report_entity: ^doc.Entity
report_name:   string

report_of :: proc(pkg: ^doc.Pkg) -> ^Report_Pkg {
	// kept to the end, whatever allocator the caller was using
	context.allocator = runtime.default_allocator()
	r := report_pkgs[pkg]
	if r == nil {
		r = new(Report_Pkg)
		report_pkgs[pkg] = r
	}
	return r
}

report_begin :: proc(pkg: ^doc.Pkg, e: ^doc.Entity = nil, name := "") {
	report_pkg, report_entity, report_name = pkg, e, name
}

report_end :: proc() {
	report_pkg, report_entity, report_name = nil, nil, ""
}

report_add :: proc(kind: Report_Kind, detail: string) {
	if report_pkg == nil {
		return
	}
	context.allocator = runtime.default_allocator()
	r := report_of(report_pkg)
	for issue in r.issues {
		if issue.kind == kind && issue.name == report_name && issue.detail == detail {
			return
		}
	}
	issue := Report_Issue{kind = kind, name = report_name, detail = strings.clone(detail)}
	if e := report_entity; e != nil && e.pos.file != 0 {
		issue.file = slashpath.base(str(cfg.files[e.pos.file].name))
		issue.line = int(e.pos.line)
	}
	append(&r.issues, issue)
}

decl_kind_of :: proc(e: ^doc.Entity) -> (kind: Decl_Kind, ok: bool) {
	#partial switch e.kind {
	case .Type_Name:  return .Type, true
	case .Constant:   return .Constant, true
	case .Variable:   return .Variable, true
	case .Procedure:  return .Procedure, true
	case .Proc_Group: return .Proc_Group, true
	}
	return
}

report_declaration :: proc(pkg: ^doc.Pkg, e: ^doc.Entity, name: string, docs: string) {
	kind, ok := decl_kind_of(e)
	if !ok {
		return
	}
	context.allocator = runtime.default_allocator()
	r := report_of(pkg)
	r.declared[kind] += 1
	if strings.trim_space(docs) == "" {
		append(&r.undocumented[kind], name)
		return
	}

	// what search results and previews show of it
	summary := doc_summary(docs)
	switch {
	case summary == "":
		first := strings.trim_space(strip_comment_gutter(docs))
		if end := strings.index_byte(first, '\n'); end >= 0 {
			first = strings.trim_space(first[:end])
		}
		if len(first) > 30 {
			first = fmt.tprintf("%s…", first[:30])
		}
		begins := "a code block" if strings.has_prefix(first, "```") || strings.has_prefix(first, "\t") else fmt.tprintf("`%s`", first)
		report_add(.Summary_None, fmt.tprintf("the docs begin with %s, so search and previews have no summary", begins))
	case strings.has_suffix(summary, "…"):
		report_add(.Summary_Long, "the first sentence runs past 160 characters, so search and previews cut it short")
	}

	words := strings.fields(strip_comment_gutter(docs), context.temp_allocator)
	text := strings.join(words, " ", context.temp_allocator)
	if len(text) >= DUPLICATE_MIN_LENGTH {
		owner := Docs_Owner{entity = e, name = name, groups = relation_list(pkg_relations_get(pkg).groups_by_member, e)}
		if e.pos.file != 0 {
			owner.file = slashpath.base(str(cfg.files[e.pos.file].name))
			owner.line = int(e.pos.line)
		}
		key := text if text in r.by_docs else strings.clone(text)
		owners := r.by_docs[key]
		append(&owners, owner)
		r.by_docs[key] = owners
	}
}

@(private="file")
report_duplicates :: proc(r: ^Report_Pkg) {
	// each declaration whose docs are another's, other than forms of the same procedure group
	shares_group :: proc(a, b: Docs_Owner) -> bool {
		if slice.contains(a.groups, b.entity) || slice.contains(b.groups, a.entity) {
			return true
		}
		for g in a.groups {
			if slice.contains(b.groups, g) {
				return true
			}
		}
		return false
	}
	// `sched_get_priority_max` → "sched", "get", "priority", "max"; `GetCodepointNext` → "get", "codepoint", "next"; `left16` → "left", "16"
	name_words :: proc(name: string) -> []string {
		words := make([dynamic]string, context.temp_allocator)
		start := 0
		for i in 0..=len(name) {
			is_digit :: proc(c: byte) -> bool { return '0' <= c && c <= '9' }
			boundary := i == len(name) || name[i] == '_' ||
			            i > start && 'A' <= name[i] && name[i] <= 'Z' && 'a' <= name[i-1] && name[i-1] <= 'z' ||
			            i > start && is_digit(name[i]) != is_digit(name[i-1])
			if boundary {
				if i > start {
					append(&words, strings.to_lower(name[start:i], context.temp_allocator))
				}
				start = i + 1 if i < len(name) && name[i] == '_' else i
			}
		}
		return words[:]
	}
	// as a word, or the start of one: "min" in "minimum"; but not words any docs might use, like "with"
	mentions :: proc(doc_words: []string, word: string) -> bool {
		switch word {
		case "with", "from", "and", "for", "the", "into", "onto", "has", "not", "all", "any", "new", "get", "set", "use":
			return false
		}
		if len(word) < 3 {
			return false
		}
		for w in doc_words {
			if strings.has_prefix(w, word) {
				return true
			}
		}
		return false
	}

	first := len(r.issues)
	for text, owners in r.by_docs {
		if len(owners) < 2 {
			continue
		}
		doc_words := strings.fields(strings.to_lower(text, context.temp_allocator), context.temp_allocator)
		for &w in doc_words {
			w = strings.trim(w, "`.,;:()[]*\"'")
		}
		slice.sort_by(owners[:], proc(a, b: Docs_Owner) -> bool { return a.name < b.name })
		// docs shared on purpose say nothing of either name's difference; copied ones describe the other declaration
		for a in owners {
			for b in owners {
				if a.entity == b.entity || a.name == b.name || shares_group(a, b) {
					continue
				}
				own, other := name_words(a.name), name_words(b.name)
				describes_self, describes_other := false, false
				for w in own {
					if !slice.contains(other, w) && mentions(doc_words, w) {
						describes_self = true
					}
				}
				for w in other {
					if !slice.contains(own, w) && mentions(doc_words, w) {
						describes_other = true
					}
				}
				if describes_other && !describes_self {
					append(&r.issues, Report_Issue{
						kind   = .Duplicate,
						name   = a.name,
						detail = fmt.aprintf("the docs are the same as `%s`'s, and describe it rather than this", b.name, allocator = runtime.default_allocator()),
						file   = a.file,
						line   = a.line,
					})
					break
				}
			}
		}
	}
	slice.sort_by(r.issues[first:], proc(a, b: Report_Issue) -> bool { return a.name < b.name })
}

@(private="file")
param_list_names :: proc(lines: []string) -> (names: [dynamic]string, ok: bool) {
	names = make([dynamic]string, context.temp_allocator)
	// `- name: description` items, as format_param_lists takes them
	for line in lines {
		text := strings.trim_space(line)
		switch {
		case strings.has_prefix(text, "- "), strings.has_prefix(text, "* "):
			colon := strings.index_byte(text, ':')
			if colon < 0 {
				return
			}
			for untrimmed in strings.split(text[2:colon], ",", context.temp_allocator) {
				name := strings.trim_left(strings.trim_space(untrimmed), "$")
				if name == "" {
					return
				}
				for r, i in name {
					if !(r == '_' || 'a' <= r && r <= 'z' || 'A' <= r && r <= 'Z' || i > 0 && '0' <= r && r <= '9') {
						return
					}
				}
				append(&names, name)
			}
		case text == "":
			return names, len(names) > 0
		case line[0] == ' ' || line[0] == '\t':
			// the item before, continued
		case:
			return names, len(names) > 0
		}
	}
	return names, len(names) > 0
}

report_check_params :: proc(docs: string, e: ^doc.Entity) {
	if report_pkg == nil {
		return
	}
	#partial switch e.kind {
	case .Procedure, .Type_Name:
	case:
		return
	}
	t := base_type(cfg.types[e.type])
	if t.kind != .Proc {
		return
	}
	tuples := array(t.types)

	lines := strings.split_lines(strip_comment_gutter(docs), context.temp_allocator)
	for line, i in lines {
		title := strings.trim_space(line)
		which: int
		switch title {
		case "Inputs:":  which = 0
		case "Returns:": which = 1
		case:            continue
		}
		listed := param_list_names(lines[i+1:]) or_continue

		declared := make([dynamic]string, context.temp_allocator)
		unnamed_results := false
		if which < len(tuples) && tuples[which] != 0 {
			for index in array(cfg.types[tuples[which]].entities) {
				name := strings.trim_left(str(cfg.entities[index].name), "$")
				if name == "" || name == "_" {
					unnamed_results ||= which == 1
					continue
				}
				append(&declared, name)
			}
		}
		if unnamed_results {
			// described, not named
			continue
		}

		for name in listed {
			if !slice.contains(declared[:], name) {
				report_add(.Unknown_Param, fmt.tprintf("%s names `%s`, which the signature doesn't have", title, name))
			}
		}
		for name in declared {
			if !slice.contains(listed[:], name) && !conventionally_unlisted(tuples[which], name) {
				report_add(.Missing_Param, fmt.tprintf("%s leaves out `%s`", title, name))
			}
		}
	}
}

// `loc := #caller_location`, `gen := context.random_generator`
@(private="file")
conventionally_unlisted :: proc(tuple: doc.Type_Index, name: string) -> bool {
	for index in array(cfg.types[tuple].entities) {
		param := &cfg.entities[index]
		if strings.trim_left(str(param.name), "$") == name {
			init := str(param.init_string)
			return init == "#caller_location" || strings.has_prefix(init, "context.")
		}
	}
	return false
}

report_check_naming :: proc(docs: string, pkg: ^doc.Pkg, e: ^doc.Entity, name: string) {
	if report_pkg == nil || strings.trim_space(docs) == "" {
		return
	}
	text := strip_comment_gutter(docs)

	if _, deprecated := find_entity_attribute(e, "deprecated"); !deprecated {
		for line in strings.split_lines(text, context.temp_allocator) {
			t := strings.to_lower(strings.trim_space(line), context.temp_allocator)
			if strings.has_prefix(t, "deprecated") || strings.contains(t, " is deprecated") || strings.contains(t, " are deprecated") {
				report_add(.Deprecated_Unmarked, "the docs call it deprecated, but it isn't marked `@(deprecated)`")
				break
			}
		}
	}

	// `builder_cap` in the docs of `builder_len`, of the same kind, and neither's name the start of the other's
	first := strings.trim_left_space(text)
	if end := strings.index_any(first, " \t\n"); end >= 0 {
		first = first[:end]
	}
	quoted := strings.has_prefix(first, "`")
	first = strings.trim(first, "`*")
	first = strings.trim_right(first, ".,:;()")
	// a word, like "Normalize" or "pop", rather than a name, unless it's quoted or snake_case
	if !quoted && !strings.contains_rune(strings.trim(first, "_"), '_') {
		return
	}
	if first == "" || strings.contains(name, first) || strings.contains(first, name) || is_local_name(e, first) {
		return
	}
	other, ok := kinds_by_name(pkg)[first]
	if !ok {
		return
	}
	same_kind :: proc(a, b: doc.Entity_Kind) -> bool {
		is_proc :: proc(k: doc.Entity_Kind) -> bool { return k == .Procedure || k == .Proc_Group }
		return a == b || is_proc(a) && is_proc(b)
	}
	if same_kind(other, e.kind) {
		report_add(.Other_Name, fmt.tprintf("the docs begin with `%s`, another declaration", first))
	}
}

@(private="file")
kinds_by_name :: proc(pkg: ^doc.Pkg) -> map[string]doc.Entity_Kind {
	@(static) cache: map[^doc.Pkg]map[string]doc.Entity_Kind
	if kinds, ok := cache[pkg]; ok {
		return kinds
	}
	context.allocator = runtime.default_allocator()
	kinds := make(map[string]doc.Entity_Kind)
	for entry in array(pkg.entries) {
		kinds[str(entry.name)] = cfg.entities[entry.entity].kind
	}
	cache[pkg] = kinds
	return kinds
}

@(private="file")
example_error: struct {
	line: int,
	msg:  string,
}
@(private="file")
example_offset: int
@(private="file")
example_file: ^ast.File

@(private="file")
parses :: proc(src: string) -> bool {
	p := parser.default_parser()
	p.err = proc(pos: tokenizer.Pos, msg: string, args: ..any) {
		if example_error.msg == "" {
			example_error.line = pos.line - example_offset
			example_error.msg  = fmt.tprintf(msg, ..args)
		}
	}
	p.warn = proc(pos: tokenizer.Pos, msg: string, args: ..any) {}
	example_file = new(ast.File)
	example_file^ = {src = src, fullpath = "example.odin"}
	example_error = {}
	return parser.parse_file(&p, example_file) && p.error_count == 0
}

@(private="file")
package_names :: proc() -> map[string]bool {
	// what examples may write `name.` for: every package's directory and declared name, and the conventional aliases
	@(static) names: map[string]bool
	if len(names) == 0 {
		context.allocator = runtime.default_allocator()
		for c in cfg.collections {
			for path, pkg in c.pkgs {
				if path != "" {
					names[strings.clone(slashpath.base(path))] = true
				}
				// merged packages' strings are in their own doc files
				names[strings.clone(doc.from_string(cfg.pkg_to_header[pkg], pkg.name))] = true
			}
		}
		for _, alias in cfg.import_aliases {
			names[alias] = true
		}
		delete_key(&names, "builtin")
	}
	return names
}

@(private="file")
has_imports :: proc(file: ^ast.File) -> bool {
	for decl in file.decls {
		if decl != nil {
			if _, ok := decl.derived.(^ast.Import_Decl); ok {
				return true
			}
		}
	}
	return false
}

@(private="file")
declares_procedure :: proc(file: ^ast.File) -> bool {
	for decl in file.decls {
		if decl == nil {
			continue
		}
		value_decl := decl.derived.(^ast.Value_Decl) or_continue
		for value in value_decl.values {
			if value != nil {
				if _, ok := value.derived.(^ast.Proc_Lit); ok {
					return true
				}
			}
		}
	}
	return false
}

@(private="file")
check_example_imports :: proc(file: ^ast.File) {
	imported := make(map[string]bool, 8)
	for decl in file.decls {
		if decl == nil {
			continue
		}
		imp := decl.derived.(^ast.Import_Decl) or_continue
		name := imp.name.text
		if name == "" {
			path := strings.trim(imp.relpath.text, "\"`")
			if _, colon, rest := strings.partition(path, ":"); colon != "" {
				path = rest
			}
			name = slashpath.base(path)
		}
		imported[name] = true
	}

	Names :: struct {
		declared, used: map[string]bool,
	}
	names := Names{make(map[string]bool, 16), make(map[string]bool, 16)}
	visitor := ast.Visitor{
		data  = &names,
		visit = proc(v: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
			if node == nil {
				return nil
			}
			names := (^Names)(v.data)
			declare :: proc(names: ^Names, exprs: []^ast.Expr) {
				for e in exprs {
					if e == nil {
						continue
					}
					#partial switch x in e.derived {
					case ^ast.Ident:
						names.declared[x.name] = true
					case ^ast.Poly_Type:
						if x.type != nil {
							names.declared[x.type.name] = true
						}
					}
				}
			}
			#partial switch n in node.derived {
			case ^ast.Value_Decl:  declare(names, n.names)
			case ^ast.Field:       declare(names, n.names)
			case ^ast.Range_Stmt:  declare(names, n.vals)
			case ^ast.Assign_Stmt: declare(names, n.lhs)
			case ^ast.Selector_Expr:
				if n.expr == nil {
					break
				}
				if id, ok := n.expr.derived.(^ast.Ident); ok {
					names.used[id.name] = true
				}
			}
			return v
		},
	}
	for decl in file.decls {
		if decl != nil {
			ast.walk(&visitor, decl)
		}
	}

	missing := make([dynamic]string, 0, 4)
	known := package_names()
	for name in names.used {
		if !imported[name] && !names.declared[name] && name in known {
			append(&missing, name)
		}
	}
	slice.sort(missing[:])
	for name in missing {
		report_add(.Missing_Import, fmt.tprintf("the example uses `%s` without importing it", name))
	}
}

@(private="file")
misspellings :: proc() -> map[string]string {
	@(static) words: map[string]string
	if len(words) == 0 {
		context.allocator = runtime.default_allocator()
		text := string(#load("resources/misspellings.txt"))
		for raw in strings.split_lines_iterator(&text) {
			line := strings.trim_space(raw)
			if line == "" || line[0] == '#' {
				continue
			}
			wrong, _, right := strings.partition(line, " ")
			words[wrong] = strings.trim_space(right)
		}
	}
	return words
}

report_check_spelling :: proc(lines: []string) {
	// prose only: not in `code`, links, URLs, or names like `foo_bar` and `pkg.name`
	if report_pkg == nil {
		return
	}
	words := misspellings()
	is_letter :: proc(c: byte) -> bool {
		return 'a' <= c && c <= 'z' || 'A' <= c && c <= 'Z'
	}
	is_name_part :: proc(c: byte) -> bool {
		return c == '_' || c == '.' || '0' <= c && c <= '9'
	}
	for line in lines {
		for i := 0; i < len(line); /**/ {
			c := line[i]
			switch {
			case c == '`':
				end := strings.index_byte(line[i+1:], '`')
				i = len(line) if end < 0 else i + 1 + end + 1
			case c == '[' && strings.has_prefix(line[i:], "[["):
				end := strings.index(line[i:], "]]")
				i = len(line) if end < 0 else i + end + 2
			case c == ']' && strings.has_prefix(line[i:], "]("):
				end := strings.index_byte(line[i:], ')')
				i = len(line) if end < 0 else i + end + 1
			case strings.has_prefix(line[i:], "http://") || strings.has_prefix(line[i:], "https://"):
				for i < len(line) && line[i] != ' ' && line[i] != '\t' {
					i += 1
				}
			case is_letter(c):
				start := i
				for i < len(line) && is_letter(line[i]) {
					i += 1
				}
				word := line[start:i]
				if start > 0 && is_name_part(line[start-1]) || i < len(line) && (is_name_part(line[i]) && !(line[i] == '.' && (i+1 == len(line) || line[i+1] == ' '))) {
					for i < len(line) && (is_letter(line[i]) || is_name_part(line[i])) {
						i += 1
					}
					continue
				}
				if right, ok := words[strings.to_lower(word, context.temp_allocator)]; ok {
					report_add(.Misspelled, fmt.tprintf("`%s` should be `%s`", word, right))
				}
			case:
				i += 1
			}
		}
	}
}


report_check_example :: proc(lines: []string) {
	if report_pkg == nil {
		return
	}
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	context.allocator = context.temp_allocator

	// either a file, as most examples are, or statements, with any imports first

	as_file  := strings.builder_make()
	as_stmts := strings.builder_make()
	// some name their own package
	example_offset = 0
	for line in lines {
		text := strings.trim_space(line)
		if text != "" && !strings.has_prefix(text, "//") {
			if !strings.has_prefix(text, "package ") {
				strings.write_string(&as_file,  "package example\n")
				strings.write_string(&as_stmts, "package example\n")
				example_offset = 1
			}
			break
		}
	}
	opened := false
	for line in lines {
		code := strings.trim_prefix(line, "\t")
		text := strings.trim_space(code)
		// `...` and `{ ... }` stand for whatever goes there
		if text == "..." {
			code, text = "", ""
		}
		code, _ = strings.replace_all(code, "{ ... }", "{}")
		if !opened && text != "" && !strings.has_prefix(text, "import ") && !strings.has_prefix(text, "package ") && !strings.has_prefix(text, "//") {
			// on the same line, so the line numbers agree
			strings.write_string(&as_stmts, "example :: proc() {")
			opened = true
		}
		strings.write_string(&as_file, code)
		strings.write_string(&as_stmts, code)
		strings.write_byte(&as_file, '\n')
		strings.write_byte(&as_stmts, '\n')
	}
	if opened {
		strings.write_string(&as_stmts, "}\n")
	}

	if parses(strings.to_string(as_file)) {
		if has_imports(example_file) || declares_procedure(example_file) {
			check_example_imports(example_file)
		}
		return
	}
	first := example_error
	if parses(strings.to_string(as_stmts)) {
		// statements alone, with no imports, are a sketch of the calls rather than a program
		if has_imports(example_file) {
			check_example_imports(example_file)
		}
		return
	}
	// the attempt that got further is the likelier reading
	err := first if first.line >= example_error.line else example_error
	report_add(.Bad_Example, fmt.tprintf("line %d: %s", err.line, err.msg))
}

generate_report :: proc(b: ^strings.Builder, collections: []^Collection) {
	w := strings.to_writer(b)
	os.make_directory("report")

	strings.builder_reset(b)
	fmt.wprintf(w, `{{"generated": "%s", "packages": [`, build_date())
	first := true
	for c in collections {
		paths := make([dynamic]string, context.temp_allocator)
		for path in c.pkgs {
			append(&paths, path)
		}
		slice.sort(paths[:])

		for path in paths {
			pkg := c.pkgs[path]
			r := report_pkgs[pkg] or_continue
			report_duplicates(r)
			if !first {
				io.write_string(w, ",")
			}
			first = false

			tree_path := fmt.tprintf("%s/%s", c.name, path) if path != "" else c.name
			io.write_string(w, "\n{\"path\": ")
			write_json_string(w, tree_path)
			io.write_string(w, ", \"import\": ")
			write_json_string(w, fmt.tprintf("%s:%s", c.name, path))
			io.write_string(w, ", \"url\": ")
			write_json_string(w, fmt.tprintf("%s/%s/", c.base_url, path) if path != "" else fmt.tprintf("%s/", c.base_url))
			io.write_string(w, ", \"source\": ")
			write_json_string(w, fmt.tprintf("%s/%s", c.source_url, path))
			fmt.wprintf(w, `, "overview": %v, "dense": %v`, r.has_overview, is_dense_pkg(pkg))
			if title, url := external_docs_of(pkg); url != "" {
				io.write_string(w, `, "external": `)
				write_json_string(w, title)
				io.write_string(w, `, "external_url": `)
				write_json_string(w, url)
			}
			io.write_string(w, `, "declared": {`)
			for kind, i in Decl_Kind {
				fmt.wprintf(w, `%s"%s": %d`, ", " if i > 0 else "", DECL_KIND_CODES[kind], r.declared[kind])
			}
			io.write_string(w, `}, "undocumented": {`)
			for kind, i in Decl_Kind {
				fmt.wprintf(w, `%s"%s": [`, ", " if i > 0 else "", DECL_KIND_CODES[kind])
				for name, j in r.undocumented[kind] {
					if j > 0 {
						io.write_byte(w, ',')
					}
					write_json_string(w, name)
				}
				io.write_string(w, "]")
			}
			io.write_string(w, `}, "issues": [`)
			for issue, i in r.issues {
				if i > 0 {
					io.write_byte(w, ',')
				}
				fmt.wprintf(w, `["%s", `, REPORT_KIND_CODES[issue.kind])
				write_json_string(w, issue.name)
				io.write_string(w, ", ")
				write_json_string(w, issue.detail)
				io.write_string(w, ", ")
				write_json_string(w, issue.file)
				fmt.wprintf(w, ", %d]", issue.line)
			}
			io.write_string(w, "]}")
		}
	}
	io.write_string(w, "\n]}\n")
	if nil != os.write_entire_file("report/data.json", b.buf[:]) {
		errorf("unable to write the report/data.json file")
	}

	strings.builder_reset(b)
	write_html_header(w, "Documentation report - pkg.odin-lang.org", .Full_Width,
	                  extra_head = `<meta name="robots" content="noindex"><link rel="stylesheet" href="/report/report.css">`)
	io.write_string(w, `<div id="odin-report" class="odin-report">
<h1>Documentation report</h1>
<p class="odin-report-lede">What the docs are missing or get wrong, package by package.</p>
<noscript>The report needs JavaScript; its data is in <a href="/report/data.json">data.json</a>.</noscript>
</div>
`)
	io.write(w, #load("resources/footer.txt.html"))
	io.write_string(w, `<script src="/report/report.js"></script>`+"\n</body>\n</html>\n")
	if nil != os.write_entire_file("report/index.html", b.buf[:]) {
		errorf("unable to write the report/index.html file")
	}
	if nil != os.write_entire_file("report/report.js", #load("resources/report.js")) {
		errorf("unable to write the report/report.js file")
	}
	if nil != os.write_entire_file("report/report.css", #load("resources/report.css")) {
		errorf("unable to write the report/report.css file")
	}
}
