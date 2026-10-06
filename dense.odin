package odin_html_docs

import "base:intrinsics"
import "core:fmt"
import "core:io"
import "core:path/slashpath"
import "core:slice"
import "core:strings"

import doc "core:odin/doc-format"

is_dense_pkg :: proc(pkg: ^doc.Pkg) -> bool {
	import_path := pkg_import_path(pkg)
	for pattern in cfg.dense_packages {
		if strings.has_suffix(pattern, "/*") {
			if strings.has_prefix(import_path, pattern[:len(pattern)-1]) {
				return true
			}
		} else if import_path == pattern {
			return true
		}
	}
	return false
}

@(private="file")
calling_convention :: proc(e: ^doc.Entity) -> string {
	t := cfg.types[e.type]
	if t.kind != .Proc {
		return ""
	}
	switch cc := str(t.calling_convention); cc {
	case "odin": return ""
	case "cdecl": return "c"
	case: return cc
	}
}

@(private="file")
write_dense_signature :: proc(writer: ^Type_Writer, e: ^doc.Entity, common_cc: string) {
	w := writer.w
	t := cfg.types[e.type]
	if t.kind != .Proc {
		write_type(writer, t, {})
		return
	}
	// `(dst: GPR64, src: Mem64) -> Instruction`: the `proc` and the usual calling convention are said once, above
	if cc := calling_convention(e); cc != common_cc {
		io.write_string(w, `<span class="keyword-type">proc</span>`)
		if cc != "" {
			io.write_string(w, ` <span class="string">`)
			io.write_quoted_string(w, cc)
			io.write_string(w, "</span> ")
		}
	}
	type_flags := transmute(doc.Type_Flags_Proc)t.flags
	params  := array(t.types)[0]
	results := array(t.types)[1]
	io.write_byte(w, '(')
	write_type(writer, cfg.types[params], {})
	io.write_byte(w, ')')
	if results != 0 {
		io.write_string(w, " -> ")
		write_type(writer, cfg.types[results], {.Is_Results})
	}
	if .Diverging in type_flags {
		io.write_string(w, " -> !")
	}
	if .Optional_Ok in type_flags {
		io.write_string(w, ` <span class="directive">#optional_ok</span>`)
	}
}

@(private="file")
entry_docs :: proc(e: ^doc.Entity) -> string {
	docs := str(e.docs)
	if strings.trim_space(docs) == "" {
		docs = str(e.comment)
	}
	return docs
}

@(private="file")
write_dense_docs :: proc(w: io.Writer, pkg: ^doc.Pkg, e: ^doc.Entity, name, docs: string) {
	// the first sentence, and the rest when opened
	summary := doc_summary(docs)
	if summary == "" {
		return
	}
	if len(strings.trim_space(docs)) <= len(summary) + 1 {
		fmt.wprintf(w, `<div class="doc-dense-doc">%s</div>`, escape_html_string(summary, context.temp_allocator))
		return
	}
	fmt.wprintf(w, `<details class="doc-dense-doc"><summary>%s</summary>`, escape_html_string(summary, context.temp_allocator))
	ctx := Doc_Context{pkg = pkg, owner = fmt.tprintf("%s.%s", str(pkg.name), name), heading_prefix = name, entity = e, self_name = name}
	write_docs(w, docs, doc_ctx = &ctx)
	io.write_string(w, "</details>")
}

write_dense_procedures :: proc(w: io.Writer, pkg: ^doc.Pkg, procs, groups: []doc.Scope_Entry) {
	collection := cfg.pkg_to_collection[pkg]
	path := collection.pkg_to_path[pkg]
	writer := &Type_Writer{w = w, pkg = doc.Pkg_Index(intrinsics.ptr_sub(pkg, &cfg.pkgs[0]))}
	defer delete(writer.generic_scope)

	entry_of := make(map[^doc.Entity]doc.Scope_Entry, len(procs), context.temp_allocator)
	for entry in procs {
		entry_of[&cfg.entities[entry.entity]] = entry
	}
	in_group := make(map[^doc.Entity]bool, len(procs), context.temp_allocator)
	for entry in groups {
		for member in array(cfg.entities[entry.entity].grouped_entities) {
			if m := &cfg.entities[member]; m in entry_of {
				in_group[m] = true
			}
		}
	}

	// whichever calling convention most have is said once
	cc_counts := make(map[string]int, 4, context.temp_allocator)
	for entry in procs {
		cc_counts[calling_convention(&cfg.entities[entry.entity])] += 1
	}
	common_cc, most := "", 0
	for cc, n in cc_counts {
		if n > most || n == most && cc < common_cc {
			common_cc, most = cc, n
		}
	}

	Item :: struct {
		entry:    doc.Scope_Entry,
		is_group: bool,
	}
	items := make([dynamic]Item, 0, len(procs) + len(groups), context.temp_allocator)
	for entry in groups {
		append(&items, Item{entry, true})
	}
	for entry in procs {
		if !in_group[&cfg.entities[entry.entity]] {
			append(&items, Item{entry, false})
		}
	}
	slice.sort_by(items[:], proc(a, b: Item) -> bool {
		return str(a.entry.name) < str(b.entry.name)
	})

	fmt.wprintf(w, `<p class="doc-dense-note">One row per procedure`)
	if len(groups) > 0 {
		io.write_string(w, ", under the procedure groups they belong to")
	}
	if common_cc != "" {
		fmt.wprintf(w, `; each is a <code><span class="keyword-type">proc</span> <span class="string">"%s"</span></code> unless it says otherwise`, common_cc)
	}
	io.write_string(w, ".</p>\n")
	fmt.wprintf(w, `<table class="doc-dense" data-source="%s/%s/"`, collection.source_url, path)
	if common_cc != "" {
		fmt.wprintf(w, ` data-cc="%s"`, common_cc)
	}
	io.write_string(w, ">\n")

	emitted := make(map[^doc.Entity]bool, len(procs), context.temp_allocator)
	write_row :: proc(w: io.Writer, writer: ^Type_Writer, pkg: ^doc.Pkg, entry: doc.Scope_Entry, common_cc: string, emitted: ^map[^doc.Entity]bool) {
		e := &cfg.entities[entry.entity]
		name := str(entry.name)
		declared_here := name == str(e.name) && &cfg.pkgs[cfg.files[e.pos.file].pkg] == pkg
		// a procedure in two groups is listed in both, but only one row can be where its links go
		if e in emitted^ {
			fmt.wprintf(w, `<tr><td><a href="#%s">%s</a></td><td><code>`, name, name)
		} else {
			emitted^[e] = true
			fmt.wprintf(w, `<tr id="%s"`, name)
			if e.pos.file != 0 && e.pos.line > 0 {
				fmt.wprintf(w, ` data-src="%s#L%d"`, slashpath.base(str(cfg.files[e.pos.file].name)), e.pos.line)
			}
			fmt.wprintf(w, `><td><a href="#%s">%s</a></td><td><code>`, name, name)
		}
		write_dense_signature(writer, e, common_cc)
		io.write_string(w, "</code>")

		docs := entry_docs(e)
		if declared_here {
			report_begin(pkg, e, name)
			report_declaration(pkg, e, name, strings.trim_space(docs) != "")
			report_check_params(docs, e)
		}
		write_dense_docs(w, pkg, e, name, docs)
		report_end()
		io.write_string(w, "</td></tr>\n")
	}

	in_loose := false
	for item in items {
		e := &cfg.entities[item.entry.entity]
		name := str(item.entry.name)
		if !item.is_group {
			if !in_loose {
				io.write_string(w, "<tbody>\n")
				in_loose = true
			}
			write_row(w, writer, pkg, item.entry, common_cc, &emitted)
			continue
		}
		if in_loose {
			io.write_string(w, "</tbody>\n")
			in_loose = false
		}

		members := array(e.grouped_entities)
		io.write_string(w, `<tbody class="doc-dense-set">`+"\n")
		fmt.wprintf(w, `<tr class="doc-dense-group" id="%s"`, name)
		if e.pos.file != 0 && e.pos.line > 0 {
			fmt.wprintf(w, ` data-src="%s#L%d"`, slashpath.base(str(cfg.files[e.pos.file].name)), e.pos.line)
		}
		fmt.wprintf(w, `><th colspan="2"><a href="#%s">%s</a> <span class="doc-dense-count">%d</span>`, name, name, len(members))
		docs := entry_docs(e)
		if name == str(e.name) && &cfg.pkgs[cfg.files[e.pos.file].pkg] == pkg {
			report_begin(pkg, e, name)
			report_declaration(pkg, e, name, strings.trim_space(docs) != "")
		}
		write_dense_docs(w, pkg, e, name, docs)
		report_end()
		io.write_string(w, "</th></tr>\n")

		for member in members {
			m := &cfg.entities[member]
			if entry, ok := entry_of[m]; ok {
				write_row(w, writer, pkg, entry, common_cc, &emitted)
			} else {
				// declared elsewhere
				other := cfg.entity_to_pkg[m]
				member_name := str(m.name)
				url := doc_entity_url(other, member_name) if other != nil else ""
				fmt.wprintf(w, `<tr><td><a href="%s">%s.%s</a></td><td><code>`, url, pkg_import_name(other) if other != nil else "", member_name)
				write_dense_signature(writer, m, common_cc)
				io.write_string(w, "</code></td></tr>\n")
			}
		}
		io.write_string(w, "</tbody>\n")
	}
	if in_loose {
		io.write_string(w, "</tbody>\n")
	}
	io.write_string(w, "</table>\n")
}
