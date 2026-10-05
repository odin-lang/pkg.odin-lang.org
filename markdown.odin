package odin_html_docs

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:log"
import "core:net"
import "core:slice"
import "core:strings"

import doc "core:odin/doc-format"
import cm "vendor:commonmark"

Doc_Context :: struct {
	pkg:            ^doc.Pkg, // resolves unqualified `[[name]]` references
	owner:          string,   // named in warnings
	heading_prefix: string,   // headings only get ids when set
	headings:       ^[dynamic]Doc_Heading,
	used_ids:       map[string]int,
}

Doc_Heading :: struct {
	level:    int,
	id, text: string,
}

doc_warning_count: int

doc_warnf :: proc(format: string, args: ..any) {
	doc_warning_count += 1
	log.warnf(format, ..args)
}


build_doc_link_index :: proc() {
	for c in cfg.collections {
		for _, pkg in c.pkgs {
			header   := cfg.pkg_to_header[pkg]
			entities := doc.from_array(header, header.entities)
			pkg_name := doc.from_string(header, pkg.name)

			names: map[string]bool
			for entry in doc.from_array(header, pkg.entries) {
				e := entities[entry.entity]
				#partial switch e.kind {
				case .Invalid, .Import_Name, .Library_Name:
					continue
				}
				name := doc.from_string(header, entry.name)
				if name == "" || (name[0] == '_' && !strings.has_prefix(pkg_name, "simd")) {
					continue
				}
				names[name] = true
			}
			cfg.pkg_link_names[pkg] = names

			list := cfg.pkgs_by_name[pkg_name]
			append(&list, pkg)
			cfg.pkgs_by_name[pkg_name] = list
		}
	}
}

// `core:sys/windows`, `sys/windows`, or a package name, preferring `from` and its collection
lookup_doc_pkg :: proc(ref: string, from: ^doc.Pkg) -> ^doc.Pkg {
	if coll_name, _, path := strings.partition(ref, ":"); path != "" {
		for c in cfg.collections {
			if c.name == coll_name {
				return c.pkgs[path]
			}
		}
		return nil
	}

	from_coll := cfg.pkg_to_collection[from] if from != nil else nil
	if strings.contains(ref, "/") {
		if from_coll != nil {
			if p, ok := from_coll.pkgs[ref]; ok {
				return p
			}
		}
		for c in cfg.collections {
			if p, ok := c.pkgs[ref]; ok {
				return p
			}
		}
		return nil
	}

	collection_index :: proc(c: ^Collection) -> int {
		i, _ := slice.linear_search(cfg.collections[:], c)
		return i
	}

	best: ^doc.Pkg
	best_rank, best_path := max(int), ""
	// NOTE: ranging directly over a missing map entry currently crashes
	candidates := cfg.pkgs_by_name[ref]
	for p in candidates {
		c := cfg.pkg_to_collection[p]
		path := c.pkg_to_path[p]
		rank := (int(p != from)*4 + int(c != from_coll)*2 + int(path != ref)) * len(cfg.collections) + collection_index(c)
		if rank < best_rank || rank == best_rank && path < best_path {
			best, best_rank, best_path = p, rank, path
		}
	}
	return best
}

doc_entity_url :: proc(p: ^doc.Pkg, name: string) -> string {
	c := cfg.pkg_to_collection[p]
	if path := c.pkg_to_path[p]; path != "" {
		return fmt.tprintf("%s/%s/#%s", c.base_url, path, name)
	}
	return fmt.tprintf("%s/#%s", c.base_url, name)
}

builtin_url :: proc(page, name: string) -> (url: string, ok: bool) {
	table := builtins if page == "builtin" else intrinsics_table
	for b in table {
		if b.name == name {
			for c in cfg.collections {
				if c.name == "base" {
					return fmt.tprintf("%s/%s/#%s", c.base_url, page, name), true
				}
			}
		}
	}
	return
}

// `[[mem.Allocator]]`, `[[core:mem.Allocator]]`, `[[Allocator.procedure]]`, `[[len]]`
resolve_doc_reference :: proc(target: string, from: ^doc.Pkg) -> (url: string, ok: bool) {
	parts := strings.split(target, ".", context.temp_allocator)
	for k := len(parts)-1; k >= 1; k -= 1 {
		pkg_ref := strings.join(parts[:k], ".", context.temp_allocator)
		name := parts[k]
		switch pkg_ref {
		case "builtin", "intrinsics":
			if url, ok = builtin_url(pkg_ref, name); ok {
				return
			}
		}
		if p := lookup_doc_pkg(pkg_ref, from); p != nil && name in cfg.pkg_link_names[p] {
			return doc_entity_url(p, name), true
		}
	}
	if from != nil && parts[0] in cfg.pkg_link_names[from] {
		return doc_entity_url(from, parts[0]), true
	}
	return builtin_url("builtin", parts[0])
}


doc_link_open_tag :: proc(raw_url: string, allocator := context.temp_allocator) -> string {
	context.allocator = allocator

	url, host := raw_url, ""
	if strings.contains(raw_url, "://") {
		// Case-normalize URI per RFC 3986 §6.2.2.1
		scheme, raw_host, path, queries, fragment := net.split_url(raw_url)
		host = strings.to_lower(raw_host)
		url  = net.join_url(strings.to_lower(scheme), host, path, queries, fragment)
	}
	url, _ = strings.replace_all(url, "&", "&amp;")
	url, _ = strings.replace_all(url, `"`, "%22")
	url, _ = strings.replace_all(url, "<", "%3C")
	url, _ = strings.replace_all(url, ">", "%3E")

	if host == "" || strings.has_suffix(host, cfg.domain) {
		return fmt.aprintf(`<a href="%s">`, url)
	}
	return fmt.aprintf(`<a href="%s" target="_blank" rel="noopener noreferrer">`, url)
}

strip_comment_gutter :: proc(docs: string, allocator := context.temp_allocator) -> string {
	gutter_rest :: proc(line: string) -> (rest: string, ok: bool) {
		t := strings.trim_left_space(line)
		if !strings.has_prefix(t, "*") {
			return
		}
		if strings.trim_right(t, "*") == "" {
			return "", true
		}
		switch t[1] {
		case ' ', '\t':
			return t[2:], true
		}
		return
	}

	context.allocator = allocator

	lines := strings.split_lines(docs)

	// `/** text` leaves no gutter on the first line
	start := 0
	for start < len(lines) && strings.trim_space(lines[start]) == "" {
		start += 1
	}
	if start+1 < len(lines) && strings.trim_space(lines[start+1]) != "" {
		if _, ok := gutter_rest(lines[start]); !ok {
			start += 1
		}
	}

	is_gutter, any_bare, all_aligned := true, false, true
	non_empty := 0
	for line in lines[start:] {
		if strings.trim_space(line) == "" {
			continue
		}
		non_empty += 1
		rest, ok := gutter_rest(line)
		if !ok {
			is_gutter = false
			break
		}
		if strings.trim_space(rest) == "" {
			any_bare = true
		}
		i := 0
		for i < len(line) && line[i] == '\t' {
			i += 1
		}
		if !(i+1 < len(line) && line[i] == ' ' && line[i+1] == '*') {
			all_aligned = false
		}
	}
	if is_gutter && non_empty > 0 && (any_bare || all_aligned) {
		for &line in lines[start:] {
			line, _ = gutter_rest(line)
		}
		return strings.join(lines, "\n")
	}

	trimmed := strings.trim_left_space(docs)
	first, _, after_first := strings.partition(trimmed, "\n")
	switch {
	case strings.trim_right(strings.trim_space(first), "*") == "":
		return after_first
	case strings.has_prefix(trimmed, "*<"), strings.has_prefix(trimmed, "!<"):
		return trimmed[2:]
	case strings.has_prefix(trimmed, "* "), strings.has_prefix(trimmed, "*\t"):
		for line in strings.split_lines(after_first) {
			if strings.has_prefix(strings.trim_left_space(line), "*") {
				return docs
			}
		}
		return trimmed[1:]
	}
	return docs
}

strip_doxygen_brief :: proc(line: string) -> string {
	t := strings.trim_left_space(line)
	if strings.has_prefix(t, "* ") || strings.has_prefix(t, "*\t") {
		t = strings.trim_left_space(t[1:])
	}
	for marker in ([]string{`\brief`, "@brief"}) {
		if strings.has_prefix(t, marker) && (len(t) == len(marker) || t[len(marker)] == ' ' || t[len(marker)] == '\t') {
			return strings.trim_left_space(t[len(marker):])
		}
	}
	return line
}

// `[[ text ; url ]]` and `[[ text ; reference ]]` outside of code spans, as Markdown links, or just their text when `plain`
convert_double_bracket_links :: proc(s: string, ctx: ^Doc_Context, plain := false, allocator := context.temp_allocator) -> string {
	is_reference :: proc(s: string) -> bool {
		if s == "" || !(s[0] == '_' || ('a' <= s[0] && s[0] <= 'z') || ('A' <= s[0] && s[0] <= 'Z')) {
			return false
		}
		for c in transmute([]byte)s {
			switch c {
			case 'a'..='z', 'A'..='Z', '0'..='9', '_', '.', ':', '/':
			case:
				return false
			}
		}
		return true
	}

	b := strings.builder_make(allocator)
	latest := 0
	for i := 0; i < len(s); i += 1 {
		switch s[i] {
		case '`':
			run := 1
			for i+run < len(s) && s[i+run] == '`' {
				run += 1
			}
			fence := s[i:i+run]
			if end := strings.index(s[i+run:], fence); end >= 0 {
				i += run + end + run - 1
			} else {
				i += run - 1
			}
		case '[':
			if i+1 >= len(s) || s[i+1] != '[' {
				break
			}
			end := strings.index(s[i+2:], "]]")
			if end < 0 {
				break
			}
			inner := s[i+2:][:end]
			if strings.contains(inner, "\n") {
				break
			}
			text, target := "", strings.trim_space(inner)
			if strings.contains(inner, ";") {
				text, _, target = strings.partition(inner, ";")
				text   = strings.trim_space(text)
				target = strings.trim_space(target)
			}

			out: string
			switch {
			case strings.contains(target, "//"):
				label := text if text != "" else target
				out = label if plain else fmt.tprintf("[%s](<%s>)", label, target)
			case is_reference(target):
				if plain {
					out = text if text != "" else target
				} else if url, ok := resolve_doc_reference(target, ctx.pkg); ok {
					out = fmt.tprintf("[%s](<%s>)", text, url) if text != "" else fmt.tprintf("[`%s`](<%s>)", target, url)
				} else {
					doc_warnf("%s: unresolved reference [[%s]]", ctx.owner, target)
					out = text if text != "" else fmt.tprintf("`%s`", target)
				}
			case:
				continue
			}

			strings.write_string(&b, s[latest:i])
			strings.write_string(&b, out)
			latest = i + 2 + end + 2
			i = latest - 1
		}
	}
	strings.write_string(&b, s[latest:])
	return strings.to_string(b)
}

// The first line of prose, skipping headings
doc_summary_line :: proc(docs: string) -> string {
	docs := docs
	for line in strings.split_lines_iterator(&docs) {
		t := strings.trim_space(line)
		if t == "" || strings.has_prefix(t, "#") || strings.trim_right(t, "=-") == "" {
			continue
		}
		return t
	}
	return ""
}

markdown_plain_text :: proc(src: string, allocator := context.allocator) -> string {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(ignore = allocator == context.temp_allocator)

	ctx: Doc_Context
	root := cm.parse_document_from_string(convert_double_bracket_links(src, &ctx, plain=true), cm.DEFAULT_OPTIONS)
	defer cm.node_free(root)

	b := strings.builder_make(allocator)
	iter := cm.iter_new(root)
	defer cm.iter_free(iter)
	for {
		ev := cm.iter_next(iter)
		if ev == .Done {
			break
		}
		node := cm.iter_get_node(iter)
		t := cm.node_get_type(node)
		if ev == .Exit {
			if t >= .First_Block && t <= .Last_Block {
				strings.write_byte(&b, ' ')
			}
			continue
		}
		#partial switch t {
		case .Text, .Code, .HTML_Inline:
			strings.write_string(&b, string(cm.node_get_literal(node)))
		case .Soft_Break, .Line_Break:
			strings.write_byte(&b, ' ')
		}
	}
	return strings.trim_space(strings.to_string(b))
}

render_markdown :: proc(src: string, ctx: ^Doc_Context, allocator := context.allocator) -> string {
	new_text :: proc(literal: string) -> ^cm.Node {
		n := cm.node_new(.Text)
		cm.node_set_literal(n, strings.clone_to_cstring(literal, context.temp_allocator))
		return n
	}
	new_custom :: proc(type: cm.Node_Type, on_enter, on_exit: string) -> ^cm.Node {
		n := cm.node_new(type)
		cm.node_set_on_enter(n, strings.clone_to_cstring(on_enter, context.temp_allocator))
		cm.node_set_on_exit(n,  strings.clone_to_cstring(on_exit,  context.temp_allocator))
		return n
	}
	move_children :: proc(from, to: ^cm.Node) {
		for child := cm.node_first_child(from); child != nil; child = cm.node_first_child(from) {
			cm.node_unlink(child)
			cm.node_append_child(to, child)
		}
	}
	// Text and whether it contains a link
	inline_text :: proc(node: ^cm.Node) -> (text: string, has_link: bool) {
		b := strings.builder_make(context.temp_allocator)
		iter := cm.iter_new(node)
		defer cm.iter_free(iter)
		for {
			ev := cm.iter_next(iter)
			if ev == .Done {
				break
			}
			n := cm.iter_get_node(iter)
			#partial switch cm.node_get_type(n) {
			case .Text, .Code:
				if ev == .Enter {
					strings.write_string(&b, string(cm.node_get_literal(n)))
				}
			case .Soft_Break, .Line_Break:
				strings.write_byte(&b, ' ')
			case .Link:
				has_link = true
			}
		}
		return strings.to_string(b), has_link
	}

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(ignore = allocator == context.temp_allocator)

	root := cm.parse_document_from_string(convert_double_bracket_links(src, ctx), cm.DEFAULT_OPTIONS)
	defer cm.node_free(root)

	// The tree may only be changed once iteration has finished
	nodes := make([dynamic]^cm.Node, context.temp_allocator)
	{
		iter := cm.iter_new(root)
		defer cm.iter_free(iter)
		for {
			ev := cm.iter_next(iter)
			if ev == .Done {
				break
			}
			if ev != .Enter {
				continue
			}
			node := cm.iter_get_node(iter)
			#partial switch cm.node_get_type(node) {
			case .Heading, .HTML_Inline, .HTML_Block, .Link, .Text, .Code_Block:
				append(&nodes, node)
			}
		}
	}

	for node in nodes {
		#partial switch cm.node_get_type(node) {
		case .Heading:
			level := min(cm.node_get_heading_level(node) + 2, 6)
			if ctx.heading_prefix == "" {
				cm.node_set_heading_level(node, level)
				continue
			}
			text, has_link := inline_text(node)
			slug := slugify(text, context.temp_allocator)
			id := fmt.tprintf("%s-%s", ctx.heading_prefix, slug if slug != "" else "section")
			if n := ctx.used_ids[id]; n > 0 {
				ctx.used_ids[id] = n + 1
				id = fmt.tprintf("%s-%d", id, n + 1)
			}
			ctx.used_ids[strings.clone(id)] += 1

			block: ^cm.Node
			if has_link {
				block = new_custom(.Custom_Block, fmt.tprintf(`<h%d id="%s">`, level, id), fmt.tprintf("</h%d>", level))
			} else {
				block = new_custom(.Custom_Block,
					fmt.tprintf(`<h%d id="%s"><a class="doc-id-link" href="#%s">`, level, id, id),
					fmt.tprintf(`<span class="a-hidden">&nbsp;¶</span></a></h%d>`, level))
			}
			move_children(node, block)
			cm.node_replace(node, block)
			cm.node_free(node)
			if ctx.headings != nil {
				append(ctx.headings, Doc_Heading{int(level), strings.clone(id), strings.clone(text)})
			}
		case .Code_Block:
			// Stops highlight.js guessing a language
			if string(cm.node_get_fence_info(node)) == "" {
				cm.node_set_fence_info(node, "plaintext")
			}
		case .HTML_Inline:
			cm.node_replace(node, new_text(string(cm.node_get_literal(node))))
			cm.node_free(node)
		case .HTML_Block:
			para := cm.node_new(.Paragraph)
			cm.node_append_child(para, new_text(strings.trim_right_space(string(cm.node_get_literal(node)))))
			cm.node_replace(node, para)
			cm.node_free(node)
		case .Link:
			url := string(cm.node_get_url(node))
			scheme, _, _ := strings.partition(strings.to_lower(url, context.temp_allocator), ":")
			anchor: ^cm.Node
			switch scheme {
			case "javascript", "vbscript", "file", "data":
				anchor = new_custom(.Custom_Inline, "", "")
			case:
				anchor = new_custom(.Custom_Inline, doc_link_open_tag(url), "</a>")
			}
			move_children(node, anchor)
			cm.node_replace(node, anchor)
			cm.node_free(node)
		case .Text:
			IFF_ABBR :: `<abbr title="If and only if (⟺)">iff</abbr>`
			literal := string(cm.node_get_literal(node))
			if !strings.contains(literal, "f and only if (⟺)") {
				continue
			}
			for len(literal) > 0 {
				i := strings.index(literal, "If and only if (⟺)")
				if j := strings.index(literal, "if and only if (⟺)"); j >= 0 && (i < 0 || j < i) {
					i = j
				}
				if i < 0 {
					cm.node_insert_before(node, new_text(literal))
					break
				}
				if i > 0 {
					cm.node_insert_before(node, new_text(literal[:i]))
				}
				cm.node_insert_before(node, new_custom(.Custom_Inline, IFF_ABBR, ""))
				literal = literal[i+len("If and only if (⟺)"):]
			}
			cm.node_unlink(node)
			cm.node_free(node)
		}
	}

	html := cm.render_html(root, cm.DEFAULT_OPTIONS)
	defer cm.free(html)
	return strings.clone(string(html), allocator)
}

write_markdown :: proc(w: io.Writer, lines: []string, ctx: ^Doc_Context) {
	is_blank :: proc(s: string) -> bool {
		return strings.trim_space(s) == ""
	}
	is_list_item :: proc(s: string) -> bool {
		t := strings.trim_left_space(s)
		if strings.has_prefix(t, "- ") || strings.has_prefix(t, "* ") || strings.has_prefix(t, "+ ") {
			return true
		}
		i := 0
		for i < len(t) && '0' <= t[i] && t[i] <= '9' {
			i += 1
		}
		return i > 0 && i+1 < len(t) && (t[i] == '.' || t[i] == ')') && t[i+1] == ' '
	}

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	// Space indentation shared by every line would otherwise turn the whole block into code
	indent := max(int)
	for line in lines {
		if is_blank(line) {
			continue
		}
		n := 0
		for n < len(line) && (line[n] == ' ' || line[n] == '\t') {
			n += 1
		}
		indent = min(indent, n)
	}
	if indent == max(int) {
		return
	}
	prose := slice.clone(lines, context.temp_allocator)
	for &line in prose {
		line = "" if is_blank(line) else line[indent:]
	}

	// Fences indented four or more spaces would otherwise be indented code showing the backticks
	for i := 0; i < len(prose); i += 1 {
		t := strings.trim_left(prose[i], " ")
		n := len(prose[i]) - len(t)
		if n < 4 || !(strings.has_prefix(t, "```") || strings.has_prefix(t, "~~~")) {
			continue
		}
		end := i + 1
		for end < len(prose) && !strings.has_prefix(strings.trim_left_space(prose[end]), t[:3]) {
			end += 1
		}
		if end == len(prose) {
			continue
		}
		for &line in prose[i:end+1] {
			m := 0
			for m < n && m < len(line) && line[m] == ' ' {
				m += 1
			}
			line = line[m:]
		}
		i = end
	}

	for &line in prose {
		line = strip_doxygen_brief(line)
	}

	b := strings.builder_make(context.temp_allocator)
	for raw_line, i in prose {
		if raw_line == "" {
			strings.write_byte(&b, '\n')
			continue
		}
		line := raw_line
		if i == 0 || prose[i-1] == "" {
			for subtitle in ([]string{"Inputs:", "Returns:"}) {
				if !strings.has_prefix(line, subtitle) {
					continue
				}
				rest := strings.trim_left_space(line[len(subtitle):])
				fmt.sbprintf(&b, "**%s**", subtitle)
				switch {
				case rest != "":
					strings.write_string(&b, "\\\n")
				case i+1 < len(prose) && !is_blank(prose[i+1]) && !is_list_item(prose[i+1]):
					strings.write_string(&b, "\\")
				}
				line = rest
				break
			}
		}
		strings.write_string(&b, line)
		strings.write_byte(&b, '\n')
	}

	io.write_string(w, render_markdown(strings.to_string(b), ctx, context.temp_allocator))
}

// A single line of Markdown without the surrounding paragraph
write_markdown_inline :: proc(w: io.Writer, text: string, ctx: ^Doc_Context, code_class := "") {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	// Escape what would start a heading, list, quote, rule, or fence
	t := strings.trim_space(text)
	escape_at := -1
	if len(t) > 0 {
		switch t[0] {
		case '#', '>':
			escape_at = 0
		case '-', '*', '+', '_':
			is_rule := true
			for c in transmute([]byte)t {
				if c != t[0] && c != ' ' && c != '\t' {
					is_rule = false
					break
				}
			}
			if is_rule || len(t) == 1 || t[1] == ' ' || t[1] == '\t' {
				escape_at = 0
			}
		case '`', '~':
			if strings.has_prefix(t, "```") || strings.has_prefix(t, "~~~") {
				escape_at = 0
			}
		case '0'..='9':
			i := 0
			for i < len(t) && '0' <= t[i] && t[i] <= '9' {
				i += 1
			}
			if i < len(t) && (t[i] == '.' || t[i] == ')') && (i+1 == len(t) || t[i+1] == ' ') {
				escape_at = i
			}
		}
	}
	if escape_at >= 0 {
		t = fmt.tprintf("%s\\%s", t[:escape_at], t[escape_at:])
	}

	html := strings.trim_space(render_markdown(t, ctx, context.temp_allocator))
	if strings.has_prefix(html, "<p>") && strings.has_suffix(html, "</p>") && strings.count(html, "<p>") == 1 {
		html = html[len("<p>"):len(html)-len("</p>")]
	}
	if code_class != "" {
		html, _ = strings.replace_all(html, "<code>", fmt.tprintf(`<code class="%s">`, code_class), context.temp_allocator)
	}
	io.write_string(w, html)
}
