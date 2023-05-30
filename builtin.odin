package odin_html_docs

import doc "core:odin/doc-format"
import "core:io"
import "core:fmt"
import "core:strings"
import "core:slice"

Builtin :: struct {
	name: string,
	kind: string,
	type: string,
	comment: string,
	runtime: bool,
}

builtins := []Builtin{
	{name = "nil",          kind = "c", type = "untyped nil"},
	{name = "false",        kind = "c", type = "untyped boolean"},
	{name = "true",         kind = "c", type = "untyped boolean"},

	{name = "ODIN_OS",      kind = "c", type = "runtime.Odin_OS_Type"},
	{name = "ODIN_ARCH",    kind = "c", type = "runtime.Odin_Arch_Type"},
	{name = "ODIN_ENDIAN",  kind = "c", type = "runtime.Endian_Type"},
	{name = "ODIN_VENDOR",  kind = "c", type = "untyped string"},
	{name = "ODIN_VERSION", kind = "c", type = "untyped string"},
	{name = "ODIN_ROOT",    kind = "c", type = "untyped string"},
	{name = "ODIN_DEBUG",   kind = "c", type = "untyped boolean"},

	{name = "byte", kind = "t"},

	{name = "bool", kind = "t"},
	{name = "b8", kind = "t"},
	{name = "b16", kind = "t"},
	{name = "b32", kind = "t"},
	{name = "b64", kind = "t"},

	{name = "i8", kind = "t"},
	{name = "u8", kind = "t"},
	{name = "i16", kind = "t"},
	{name = "u16", kind = "t"},
	{name = "i32", kind = "t"},
	{name = "u32", kind = "t"},
	{name = "i64", kind = "t"},
	{name = "u64", kind = "t"},

	{name = "i128", kind = "t"},
	{name = "u128", kind = "t"},

	{name = "rune", kind = "t"},

	{name = "f16", kind = "t"},
	{name = "f32", kind = "t"},
	{name = "f64", kind = "t"},

	{name = "complex32", kind = "t"},
	{name = "complex64", kind = "t"},
	{name = "complex128", kind = "t"},

	{name = "quaternion64", kind = "t"},
	{name = "quaternion128", kind = "t"},
	{name = "quaternion256", kind = "t"},

	{name = "int", kind = "t"},
	{name = "uint", kind = "t"},
	{name = "uintptr", kind = "t"},

	{name = "rawptr", kind = "t"},
	{name = "string", kind = "t"},
	{name = "cstring", kind = "t"},
	{name = "any", kind = "t"},

	{name = "typeid", kind = "t"},

	// Endian Specific Types
	{name = "i16le", kind = "t"},
	{name = "u16le", kind = "t"},
	{name = "i32le", kind = "t"},
	{name = "u32le", kind = "t"},
	{name = "i64le", kind = "t"},
	{name = "u64le", kind = "t"},
	{name = "i128le", kind = "t"},
	{name = "u128le", kind = "t"},

	{name = "i16be", kind = "t"},
	{name = "u16be", kind = "t"},
	{name = "i32be", kind = "t"},
	{name = "u32be", kind = "t"},
	{name = "i64be", kind = "t"},
	{name = "u64be", kind = "t"},
	{name = "i128be", kind = "t"},
	{name = "u128be", kind = "t"},


	{name = "f16le", kind = "t"},
	{name = "f32le", kind = "t"},
	{name = "f64le", kind = "t"},

	{name = "f16be", kind = "t"},
	{name = "f32be", kind = "t"},
	{name = "f64be", kind = "t"},

	// Procedures
	{name = "len", kind = "b", type = "proc(array: Array_Type) -> int"},
	{name = "cap", kind = "b", type = "proc(array: Array_Type) -> int"},

	{name = "size_of"     , kind = "b", type = "proc($T: typeid) -> int"},
	{name = "align_of"    , kind = "b", type = "proc($T: typeid) -> int"},

	{name = "offset_of_selector", kind = "b", type = "proc(selector: $T) -> uintptr", comment = `e.g. offset_of(t.f), where t is an instance of the type T`},
	{name = "offset_of_member"  , kind = "b", type = "proc($T: typeid, member: $M) -> uintptr", comment = `e.g. offset_of(T, f), where T can be the type instead of a variable`},
	{name = "offset_of", kind = "b", type = "proc{offset_of_selector, offset_of_membe"},
	{name = "offset_of_by_string", kind = "b", type = "proc($T: typeid, member: string) -> uintptr", comment = `e.g. offset_of(T, "f\), where T can be the type instead of a variable`},

	{name = "type_of"     , kind = "b", type = "proc(x: expr) -> type"},
	{name = "type_info_of", kind = "b", type = "proc($T: typeid) -> ^runtime.Type_Info"},
	{name = "typeid_of"   , kind = "b", type = "proc($T: typeid) -> typeid"},

	{name = "swizzle", kind = "b", type = "proc(x: [N]T, indices: ..int) -> [len(indices)]T"},

	{name = "complex"   , kind = "b", type = "proc(real, imag: Float) -> Complex_Type"},
	{name = "quaternion", kind = "b", type = "proc(real, imag, jmag, kmag: Float) -> Quaternion_Type"},
	{name = "real"      , kind = "b", type = "proc(value: Complex_Or_Quaternion) -> Float"},
	{name = "imag"      , kind = "b", type = "proc(value: Complex_Or_Quaternion) -> Float"},
	{name = "jmag"      , kind = "b", type = "proc(value: Quaternion) -> Float"},
	{name = "kmag"      , kind = "b", type = "proc(value: Quaternion) -> Float"},
	{name = "conj"      , kind = "b", type = "proc(value: Complex_Or_Quaternion) -> Complex_Or_Quaternion"},

	{name = "expand_values", kind = "b", type = "proc(value: Struct_Or_Array) -> (A, B, C, ...)"},

	{name = "min"  , kind = "b", type = "proc(values: ..T) -> T"},
	{name = "max"  , kind = "b", type = "proc(values: ..T) -> T"},
	{name = "abs"  , kind = "b", type = "proc(value: T) -> T"},
	{name = "clamp", kind = "b", type = "proc(value, minimum, maximum: T) -> T"},

	{name = "soa_zip", kind = "b", type = "proc(slices: ...) -> #soa[]Struct"},
	{name = "soa_unzip", kind = "b", type = "proc(value: $S/#soa[]$E) -> (slices: ...)"},
}

builtin_docs := `package builtin provides documentation for Odin's predeclared identifiers. The items documented here are not actually in package builtin but here to allow for better documentation for the language's special identifiers.`

write_builtin_pkg :: proc(w: io.Writer, dir, path: string, runtime_pkg: ^doc.Pkg, collection: ^Collection) {
	fmt.wprintln(w, `<div class="row odin-main" id="pkg">`)
	defer fmt.wprintln(w, `</div>`)

	{
		fmt.wprintln(w, `<nav id="pkg-sidebar" class="col-lg-2 odin-sidebar-border navbar-light sticky-top odin-below-navbar">`)
		defer fmt.wprintln(w, `</nav>`)
		fmt.wprintln(w, `<div class="py-3">`)
		defer fmt.wprintln(w, `</div>`)

		fmt.wprintf(w, "<h4 style=\"text-transform: capitalize\">%s Library</h4>\n", collection.name)

		fmt.wprintln(w, `<ul>`)
		defer fmt.wprintln(w, `</ul>`)
	}

	fmt.wprintln(w, `<article class="col-lg-8 p-4 documentation odin-article">`)

	write_breadcrumbs(w, path, runtime_pkg, collection)

	fmt.wprintf(w, "<h1>package %s:%s", strings.to_lower(collection.name, context.temp_allocator), path)

	pkg_src_url := fmt.tprintf("%s/%s", collection.github_url, path)
	fmt.wprintf(w, "<div class=\"doc-source\"><a href=\"{0:s}\"><em>Source</em></a></div>", pkg_src_url)
	fmt.wprintf(w, "</h1>\n")

	write_search(w, .Package)

	fmt.wprintln(w, `<div id="pkg-top">`)

	{
		fmt.wprintln(w, "<h2>Overview</h2>")
		fmt.wprintln(w, "<div id=\"pkg-overview\">")
		defer fmt.wprintln(w, "</div>")

		write_docs(w, builtin_docs)
	}

	write_index :: proc(w: io.Writer, runtime_entries: []doc.Scope_Entry, name: string, kind: string, builtin_entities: ^[dynamic]doc.Scope_Entry) {
		entry_count := 0

		for entry in runtime_entries {
			e := &entities[entry.entity]
			ok := false
			for attr in array(e.attributes) {
				if str(attr.name) == "builtin" {
					ok = true
					break
				}
			}
			if !ok {
				continue
			}
			#partial switch e.kind {
			case .Constant:
				if kind == "c" {
					append(builtin_entities, entry)
					entry_count += 1
				}
			case .Type_Name:
				if kind == "t" {
					append(builtin_entities, entry)
					entry_count += 1
				}
			case .Procedure:
				if kind == "b" {
					append(builtin_entities, entry)
					entry_count += 1
				}
			case .Proc_Group:
				if kind == "g" {
					append(builtin_entities, entry)
					entry_count += 1
				}
			}
		}

		any_builtin := entry_count > 0

		for b in builtins do if b.kind == kind {
			entry_count += 1
		}


		fmt.wprintln(w, `<div>`)
		defer fmt.wprintln(w, `</div>`)

		fmt.wprintf(w, `<details class="doc-index" id="doc-index-{0:s}" aria-labelledby="#doc-index-{0:s}-header">`+"\n", name)
		fmt.wprintf(w, `<summary id="#doc-index-{0:s}-header">`+"\n", name)
		io.write_string(w, name)
		io.write_string(w, " (")
		io.write_int(w, entry_count)
		io.write_string(w, ")")
		fmt.wprintln(w, `</summary>`)
		defer fmt.wprintln(w, `</details>`)

		if entry_count == 0 {
			io.write_string(w, "<p class=\"pkg-empty-section\">This section is empty.</p>\n")
		} else {
			fmt.wprintln(w, "<ul>")
			for b in builtins do if b.kind == kind {
				fmt.wprintf(w, "<li><a href=\"#{0:s}\">{0:s}</a></li>\n", b.name)
			}

			if any_builtin {
				for entry in builtin_entities {
					e := &entities[entry.entity]
					fmt.wprintf(w, "<li><a href=\"/core/runtime\">runtime</a>.<a href=\"#{0:s}\">{0:s}</a></li>\n", str(e.name))
				}
			}

			fmt.wprintln(w, "</ul>")
		}
	}

	fmt.wprintln(w, `<div id="pkg-index">`)
	fmt.wprintln(w, `<h2>Index</h2>`)

	runtime_entries := array(runtime_pkg.entries)

	runtime_consts: [dynamic]doc.Scope_Entry
	runtime_types:  [dynamic]doc.Scope_Entry
	runtime_procs:  [dynamic]doc.Scope_Entry
	runtime_groups: [dynamic]doc.Scope_Entry
	defer delete(runtime_consts)
	defer delete(runtime_types)
	defer delete(runtime_procs)
	defer delete(runtime_groups)

	slice.sort_by_key(runtime_consts[:], entity_key)
	slice.sort_by_key(runtime_types[:],  entity_key)
	slice.sort_by_key(runtime_procs[:],  entity_key)
	slice.sort_by_key(runtime_groups[:], entity_key)

	write_index(w, runtime_entries, "Constants",        "c", &runtime_consts)
	write_index(w, runtime_entries, "Types",            "t", &runtime_types)
	write_index(w, runtime_entries, "Procedures",       "b", &runtime_procs)
	write_index(w, runtime_entries, "Procedure Groups", "g", &runtime_groups)

	fmt.wprintln(w, "</div>")
	fmt.wprintln(w, "</div>")


	write_entries :: proc(w: io.Writer, runtime_pkg: ^doc.Pkg, title: string, kind: string, entries: []doc.Scope_Entry) {
		fmt.wprintf(w, "<h2 id=\"pkg-{0:s}\" class=\"pkg-header\">{0:s}</h2>\n", title)


		// builtin entries
		for b in builtins do if b.kind == kind {
			fmt.wprintln(w, `<div class="pkg-entity">`)
			defer fmt.wprintln(w, `</div>`)

			name := b.name

			fmt.wprintf(w, "<h3 id=\"{0:s}\"><span><a class=\"doc-id-link\" href=\"#{0:s}\">{0:s}", name)
			fmt.wprintf(w, "<span class=\"a-hidden\">&nbsp;¶</span></a></span>")
			fmt.wprintf(w, "</h3>\n")
			fmt.wprintln(w, `<div>`)

			switch b.kind {
			case "c", "t":
				fmt.wprint(w, `<pre class="doc-code">`)
				fmt.wprintf(w, "%s :: %s", name, name)
				fmt.wprintln(w, "</pre>")
			case "b":
				fmt.wprint(w, `<pre class="doc-code">`)
				fmt.wprintf(w, "%s :: %s {…}", name, b.type)
				fmt.wprintln(w, "</pre>")
			}

			fmt.wprintln(w, `</div>`)

			if len(b.comment) != 0 {
				fmt.wprintln(w, `<details class="odin-doc-toggle" open>`)
				fmt.wprintln(w, `<summary class="hideme"><span>&nbsp;</span></summary>`)
				write_docs(w, b.comment, name)
				fmt.wprintln(w, `</details>`)
			}
		}

		// @builtin package runtime entries
		for e in entries {
			fmt.wprintln(w, `<div class="pkg-entity">`)
			write_entry(w, runtime_pkg, e)
			fmt.wprintln(w, `</div>`)
		}
	}

	fmt.wprintln(w, `<section class="documentation">`)
	write_entries(w, runtime_pkg, "Constants",        "c", runtime_consts[:])
	write_entries(w, runtime_pkg, "Types",            "t", runtime_types[:])
	write_entries(w, runtime_pkg, "Procedures",       "p", runtime_procs[:])
	write_entries(w, runtime_pkg, "Procedure Groups", "g", runtime_groups[:])


	fmt.wprintf(w, `<script type="text/javascript">var odin_pkg_name = "%s";</script>`+"\n", "builtin")
}