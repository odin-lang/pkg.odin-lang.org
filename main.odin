package odin_html_docs

import doc "core:odin/doc-format"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:path/slashpath"
import "core:sort"
import "core:slice"
import "core:time"
import "core:intrinsics"

main :: proc() {
	if len(os.args) != 2 {
		errorf("expected 1 .odin-doc file")
	}
	data, ok := os.read_entire_file(os.args[1])
	if !ok {
		errorf("unable to read file:", os.args[1])
	}
	err: doc.Reader_Error
	header, err = doc.read_from_bytes(data)
	switch err {
	case .None:
	case .Header_Too_Small:
		errorf("file is too small for the file format")
	case .Invalid_Magic:
		errorf("invalid magic for the file format")
	case .Data_Too_Small:
		errorf("data is too small for the file format")
	case .Invalid_Version:
		errorf("invalid file format version")
	}
	files    = array(header.files)
	pkgs     = array(header.pkgs)
	entities = array(header.entities)
	types    = array(header.types)

	core_collection := &Collection{
		name        = "core",
		pkgs_to_use = &core_pkgs_to_use,
		github_url  = GITHUB_CORE_URL,
		base_url    = BASE_CORE_URL,
		root        = nil,
	}
	vendor_collection := &Collection{
		name =        "vendor",
		pkgs_to_use = &vendor_pkgs_to_use,
		github_url =  GITHUB_VENDOR_URL,
		base_url =    BASE_VENDOR_URL,
		root =        nil,
	}

	{
		fullpaths: [dynamic]string
		defer delete(fullpaths)

		for pkg in pkgs[1:] {
			append(&fullpaths, str(pkg.fullpath))
		}
		path_prefix := common_prefix(fullpaths[:])

		core_pkgs_to_use = make(map[string]^doc.Pkg)
		vendor_pkgs_to_use = make(map[string]^doc.Pkg)
		fullpath_loop: for fullpath, i in fullpaths {
			path := strings.trim_prefix(fullpath, path_prefix)
			pkg := &pkgs[i+1]
			if len(array(pkg.entries)) == 0 {
				continue fullpath_loop
			}

			switch {
			case strings.has_prefix(path, "core/"):
				trimmed_path := strings.trim_prefix(path, "core/")
				if strings.has_prefix(trimmed_path, "sys") {
					continue fullpath_loop
				}
				if strings.contains(trimmed_path, "/_") {
					continue fullpath_loop
				}

				core_pkgs_to_use[trimmed_path] = pkg
			case strings.has_prefix(path, "vendor/"):
				trimmed_path := strings.trim_prefix(path, "vendor/")
				if strings.contains(trimmed_path, "/_") {
					continue fullpath_loop
				}
				vendor_pkgs_to_use[trimmed_path] = pkg
			}
		}
		for path, pkg in core_pkgs_to_use {
			pkg_to_path[pkg] = path
			pkg_to_collection[pkg] = core_collection
		}
		for path, pkg in vendor_pkgs_to_use {
			pkg_to_path[pkg] = path
			pkg_to_collection[pkg] = vendor_collection
		}
	}

	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	w := strings.to_writer(&b)

	{
		strings.builder_reset(&b)
		write_html_header(w, "Packages - pkg.odin-lang.org")
		write_home_page(w)
		write_html_footer(w, true)
		os.write_entire_file("index.html", b.buf[:])
	}

	core_collection.root   = generate_directory_tree(core_pkgs_to_use)
	vendor_collection.root = generate_directory_tree(vendor_pkgs_to_use)

	generate_packages(&b, core_collection)
	generate_packages(&b, vendor_collection)

	generate_json_pkg_data(&b, core_collection, vendor_collection)
}



Header_Kind :: enum {
	Normal,
	Full_Width,
}
write_html_header :: proc(w: io.Writer, title: string, kind := Header_Kind.Normal) {
	fmt.wprintf(w, string(#load("header.txt.html")), title)

	when #config(ODIN_DOC_DEV, false) {
		io.write_string(w, "\n")
		io.write_string(w, `<script type="text/javascript" src="https://livejs.com/live.js"></script>`)
		io.write_string(w, "\n")
	}


	io.write(w, #load("header-lower.txt.html"))
	switch kind {
	case .Normal:
		io.write_string(w, `<div class="container">`+"\n")
	case .Full_Width:
		io.write_string(w, `<div class="container full-width">`+"\n")
	}
}

write_html_footer :: proc(w: io.Writer, include_directory_js: bool) {
	io.write_string(w, "\n")

	io.write(w, #load("footer.txt.html"))
	fmt.wprintf(w, "</body>\n</html>\n")
}


generate_json_pkg_data :: proc(b: ^strings.Builder, collections: ..^Collection) {
	w := strings.to_writer(b)

	strings.builder_reset(b)
	now := time.now()
	fmt.wprintf(w, "/** Generated with odin version %s (vendor %q) %s_%s @ %v */\n", ODIN_VERSION, ODIN_VENDOR, ODIN_OS, ODIN_ARCH, now)
	fmt.wprint(w, "var odin_pkg_data = {\n")
	fmt.wprintln(w, `"packages": {`)
	pkg_idx := 0
	for collection in collections {
		for path, pkg in collection.pkgs_to_use {
			entries := collection.pkg_entries_map[pkg]
			if pkg_idx != 0 {
				fmt.wprintln(w, ",")
			}
			fmt.wprintf(w, "\t\"%s\": {{\n", str(pkg.name))
			fmt.wprintf(w, "\t\t\"collection\": \"%s\",\n", collection.name)
			fmt.wprintf(w, "\t\t\"path\": \"%s/%s\",\n", collection.base_url, path)
			fmt.wprint(w, "\t\t\"entities\": [\n")
			for e, i in entries.all {
				if i != 0 { fmt.wprint(w, ",\n") }

				kind_str := ""
				switch entities[e.entity].kind {
				case .Invalid:      kind_str = ""
				case .Constant:     kind_str = "c"
				case .Variable:     kind_str = "v"
				case .Type_Name:    kind_str = "t"
				case .Procedure:    kind_str = "p"
				case .Proc_Group:   kind_str = "g"
				case .Import_Name:  kind_str = "i"
				case .Library_Name: kind_str = "l"
				case .Builtin:      kind_str = "b"
				}

				fmt.wprint(w, "\t\t\t{")
				fmt.wprintf(w, `"kind": "%s", `,  kind_str)
				fmt.wprintf(w, `"name": %q, `, str(e.name))
				fmt.wprintf(w, `"full": "%s.%s"`, str(pkg.name), str(e.name))
				fmt.wprint(w, "}")
			}
			fmt.wprint(w, "\n\t\t]")
			fmt.wprint(w, "\n\t}")
			pkg_idx += 1
	}
	}
	fmt.wprintln(w, "}};")

	os.write_entire_file("pkg-data.js", b.buf[:])
}


generate_packages :: proc(b: ^strings.Builder, collection: ^Collection) {
	w := strings.to_writer(b)

	dir := collection.name

	{
		strings.builder_reset(b)
		write_html_header(w, fmt.tprintf("%s library - pkg.odin-lang.org", dir))
		write_collection_directory(w, collection)
		write_html_footer(w, true)
		os.make_directory(dir, DIRECTORY_MODE)
		os.write_entire_file(fmt.tprintf("%s/index.html", dir), b.buf[:])
	}

	collection.pkg_entries_map = make(map[^doc.Pkg]Pkg_Entries, len(collection.pkgs_to_use))
	for _, pkg in collection.pkgs_to_use {
		collection.pkg_entries_map[pkg] = pkg_entries_gather(pkg)
	}

	for path, pkg in collection.pkgs_to_use {
		strings.builder_reset(b)
		write_html_header(w, fmt.tprintf("package %s - pkg.odin-lang.org", path), .Full_Width)
		write_pkg(w, dir, path, pkg, collection, collection.pkg_entries_map[pkg])
		write_html_footer(w, false)
		recursive_make_directory(path, dir)
		os.write_entire_file(fmt.tprintf("%s/%s/index.html", dir, path), b.buf[:])
	}
}


write_home_sidebar :: proc(w: io.Writer) {
	fmt.wprintln(w, `<nav class="col-lg-2 odin-sidebar-border navbar-light">`)
	defer fmt.wprintln(w, `</nav>`)
	fmt.wprintln(w, `<div class="sticky-top odin-below-navbar py-3">`)
	defer fmt.wprintln(w, `</div>`)

	fmt.wprintln(w, `<ul class="nav nav-pills d-flex flex-column">`)
	fmt.wprintln(w, `<li class="nav-item"><a class="nav-link" href="/core">Core Library</a></li>`)
	fmt.wprintln(w, `<li class="nav-item"><a class="nav-link" href="/vendor">Vendor Libr ary</a></li>`)
	fmt.wprintln(w, `</ul>`)
}

write_home_page :: proc(w: io.Writer) {
	fmt.wprintln(w, `<div class="row odin-main">`)
	defer fmt.wprintln(w, `</div>`)

	write_home_sidebar(w)

	fmt.wprintln(w, `<article class="col-lg-8 p-4">`)
	defer fmt.wprintln(w, `</article>`)

	fmt.wprintln(w, "<article><header>")
	fmt.wprintln(w, `<h1 class="odin-package-header">Odin Packages</h1>`)
	write_search(w, .All)
	fmt.wprintln(w, "</header></article>")
	fmt.wprintln(w, "<div>")
	defer fmt.wprintln(w, "</div>")

	fmt.wprintln(w, `<div class="mt-5">`)
	fmt.wprintln(w, `<a href="/core" class="link-primary text-decoration-node"><h3>Core Library Collection</h3></a>`)
	fmt.wprintln(w, `<p>Documentation for all the packages part of the <code>core</code> library collection.</p>`)
	fmt.wprintln(w, `</div>`)

	fmt.wprintln(w, `<div class="mt-5">`)
	fmt.wprintln(w, `<a href="/vendor" class="link-primary text-decoration-node"><h3>Vendor Library Collection</h3></a>`)
	fmt.wprintln(w, `<p>Documentation for all the packages part of the <code>vendor</code> library collection.</p>`)
	fmt.wprintln(w, `</div>`)
}


write_collection_directory :: proc(w: io.Writer, collection: ^Collection) {
	get_line_doc :: proc(pkg: ^doc.Pkg) -> (line_doc: string, ok: bool) {
		if pkg == nil {
			return
		}
		line_doc, _, _ = strings.partition(str(pkg.docs), "\n")
		line_doc = strings.trim_space(line_doc)
		if line_doc == "" {
			return
		}
		switch {
		case strings.has_prefix(line_doc, "*"):
			return "", false
		case strings.has_prefix(line_doc, "Copyright"):
			return "", false
		}
		return line_doc, true
	}


	fmt.wprintln(w, `<div class="row odin-main">`)
	defer fmt.wprintln(w, `</div>`)


	write_home_sidebar(w)

	fmt.wprintln(w, `<article class="col-lg-10 p-4">`)
	defer fmt.wprintln(w, `</article>`)
	{
		fmt.wprintln(w, `<article class="p-4">`)
		fmt.wprintln(w, `<header class="collection-header">`)
		fmt.wprintf(w, "<h1 style=\"text-transform: capitalize\">%s Library Collection</h1>\n", collection.name)
		fmt.wprintln(w, "<ul>")
		fmt.wprintf(w, "<li>License: <a href=\"{0:s}\">BSD-3-Clause</a></li>\n", GITHUB_LICENSE_URL)
		fmt.wprintf(w, "<li>Repository: <a href=\"{0:s}\">{0:s}</a></li>\n", collection.github_url)
		fmt.wprintln(w, "</ul>")

		write_search(w, .Collection)

		fmt.wprintln(w, "</header>")
		fmt.wprintln(w, "</article>")
		fmt.wprintln(w, `<hr class="collection-hr">`)
	}

	fmt.wprintln(w, "<header>")
	fmt.wprintln(w, `<h2><i class="bi bi-folder"></i>Directories</h2>`)
	fmt.wprintln(w, "</header>")

	fmt.wprintln(w, "<div>")
	fmt.wprintln(w, "\t<table class=\"doc-directory mt-4 mb-4\">")
	fmt.wprintln(w, "\t\t<tbody>")

	for dir in collection.root.children {
		if len(dir.children) != 0 {
			fmt.wprint(w, `<tr aria-controls="`)
			for child in dir.children {
				fmt.wprintf(w, "pkg-%s ", str(child.pkg.name))
			}
			fmt.wprint(w, `" class="directory-pkg"><td class="pkg-line pkg-name" data-aria-owns="`)
			for child in dir.children {
				fmt.wprintf(w, "pkg-%s ", str(child.pkg.name))
			}
			fmt.wprintf(w, `" id="pkg-%s">`, dir.dir)
		} else {
			fmt.wprintf(w, `<tr id="pkg-%s" class="directory-pkg"><td class="pkg-name">`, dir.dir)
		}

		if dir.pkg != nil {
			fmt.wprintf(w, `<a href="%s/%s">%s</a>`, collection.base_url, dir.path, dir.name)
		} else {
			fmt.wprintf(w, "%s", dir.name)
		}
		io.write_string(w, `</td>`)
		io.write_string(w, `<td class="pkg-line pkg-line-doc">`)
		if line_doc, ok := get_line_doc(dir.pkg); ok {
			write_doc_line(w, line_doc)
		} else {
			io.write_string(w, `&nbsp;`)
		}
		io.write_string(w, `</td>`)
		fmt.wprintf(w, "</tr>\n")

		for child in dir.children {
			assert(child.pkg != nil)
			fmt.wprintf(w, `<tr id="pkg-%s" class="directory-pkg directory-child"><td class="pkg-line pkg-name">`, str(child.pkg.name))
			fmt.wprintf(w, `<a href="%s/%s/">%s</a>`, collection.base_url, child.path, child.name)
			io.write_string(w, `</td>`)

			line_doc, _, _ := strings.partition(str(child.pkg.docs), "\n")
			line_doc = strings.trim_space(line_doc)
			io.write_string(w, `<td class="pkg-line pkg-line-doc">`)
			if line_doc, ok := get_line_doc(child.pkg); ok {
				write_doc_line(w, line_doc)
			} else {
				io.write_string(w, `&nbsp;`)
			}
			io.write_string(w, `</td>`)

			fmt.wprintf(w, "</td>")
			fmt.wprintf(w, "</tr>\n")
		}
	}

	fmt.wprintln(w, "\t\t</tbody>")
	fmt.wprintln(w, "\t</table>")
	fmt.wprintln(w, "</div>")
}

write_where_clauses :: proc(w: io.Writer, where_clauses: []doc.String) {
	if len(where_clauses) != 0 {
		io.write_string(w, " where ")
		for clause, i in where_clauses {
			if i > 0 {
				io.write_string(w, ", ")
			}
			io.write_string(w, str(clause))
		}
	}
}


Write_Type_Flag :: enum {
	Is_Results,
	Variadic,
	Allow_Indent,
	Poly_Names,
	Ignore_Name,
	Allow_Multiple_Lines,
}
Write_Type_Flags :: distinct bit_set[Write_Type_Flag]
Type_Writer :: struct {
	w:      io.Writer,
	pkg:    doc.Pkg_Index,
	indent: int,
	generic_scope: map[string]bool,
}

calc_name_width :: proc(type_entities: []doc.Entity_Index) -> (name_width: int) {
	for entity_index in type_entities {
		e := &entities[entity_index]
		name := str(e.name)
		name_width = max(len(name), name_width)
	}
	return
}

write_type :: proc(using writer: ^Type_Writer, type: doc.Type, flags: Write_Type_Flags) {
	write_param_entity :: proc(using writer: ^Type_Writer, e, next_entity: ^doc.Entity, flags: Write_Type_Flags, name_width := 0) {
		name := str(e.name)

		write_padding :: proc(w: io.Writer, name: string, name_width: int) {
			for _ in 0..<name_width-len(name) {
				io.write_byte(w, ' ')
			}
		}

		if .Param_Using     in e.flags { io.write_string(w, `<span class="keyword-type"> using</span> `)      }
		if .Param_Const     in e.flags { io.write_string(w, `<span class="keyword-type"> #const</span> `)     }
		if .Param_Auto_Cast in e.flags { io.write_string(w, `<span class="keyword-type"> #auto_cast</span> `) }
		if .Param_CVararg   in e.flags { io.write_string(w, `<span class="keyword-type"> #c_vararg</span> `)  }
		if .Param_No_Alias  in e.flags { io.write_string(w, `<span class="keyword-type"> #no_alias</span> `)  }
		if .Param_Any_Int   in e.flags { io.write_string(w, `<span class="keyword-type"> #any_int</span> `)   }

		init_string := str(e.init_string)
		switch {
		case init_string == "#caller_location":
			assert(name != "")
			io.write_string(w, name)
			io.write_string(w, " := ")
			fmt.wprintf(w, `<a href="%s/runtime/#Source_Code_Location">`, BASE_CORE_URL)
			io.write_string(w, init_string)
			io.write_string(w, `</a>`)
		case strings.has_prefix(init_string, "context."):
			io.write_string(w, name)
			io.write_string(w, " := ")
			fmt.wprintf(w, `<a href="%s/runtime/#Context">`, BASE_CORE_URL)
			io.write_string(w, init_string)
			io.write_string(w, `</a>`)
		case:
			the_type := types[e.type]
			type_flags := flags - {.Is_Results}
			if .Param_Ellipsis in e.flags {
				type_flags += {.Variadic}
			}

			#partial switch e.kind {
			case .Constant:
				assert(name != "")
				io.write_byte(w, '$')
				io.write_string(w, name)
				if name != "" && init_string == "" && next_entity != nil && e.field_group_index >= 0 {
					if e.field_group_index == next_entity.field_group_index && e.type == next_entity.type {
						return
					}
				}

				generic_scope[name] = true
				if !is_type_untyped(the_type) {
					io.write_string(w, ": ")
					write_padding(w, name, name_width)
					write_type(writer, the_type, type_flags)
					io.write_string(w, " = ")
					io.write_string(w, init_string)
				} else {
					io.write_string(w, " := ")
					io.write_string(w, init_string)
				}
				return

			case .Variable:
				if name != "" && init_string == "" && next_entity != nil && e.field_group_index >= 0 {
					if e.field_group_index == next_entity.field_group_index && e.type == next_entity.type {
						io.write_string(w, name)
						return
					}
				}
				if .Ignore_Name not_in flags {
					if name != "" {
						io.write_string(w, name)
						io.write_string(w, ": ")
						write_padding(w, name, name_width)
					}
				}
				write_type(writer, the_type, type_flags)
			case .Type_Name:

				io.write_byte(w, '$')
				io.write_string(w, name)
				generic_scope[name] = true
				io.write_string(w, ": ")
				write_padding(w, name, name_width)
				if the_type.kind == .Generic {
					io.write_string(w, "typeid")
					if ts := array(the_type.types); len(ts) == 1 {
						io.write_byte(w, '/')
						write_type(writer, types[ts[0]], type_flags)
					}
				} else {
					write_type(writer, the_type, type_flags)
				}
			}

			if init_string != "" {
				io.write_string(w, " = ")
				io.write_string(w, init_string)
			}
		}
	}
	write_poly_params :: proc(using writer: ^Type_Writer, type: doc.Type, flags: Write_Type_Flags) {
		if type.polymorphic_params != 0 {
			io.write_byte(w, '(')
			write_type(writer, types[type.polymorphic_params], flags+{.Poly_Names})
			io.write_byte(w, ')')
		}

		write_where_clauses(w, array(type.where_clauses))
	}
	do_indent :: proc(using writer: ^Type_Writer, flags: Write_Type_Flags) {
		if .Allow_Indent not_in flags {
			return
		}
		for _ in 0..<indent {
			io.write_byte(w, '\t')
		}
	}
	do_newline :: proc(using writer: ^Type_Writer, flags: Write_Type_Flags) {
		if .Allow_Indent in flags {
			io.write_byte(w, '\n')
		}
	}

	calc_field_width :: proc(type_entities: []doc.Entity_Index) -> (field_width: int) {
		name_width := calc_name_width(type_entities)

		for entity_index in type_entities {
			e := &entities[entity_index]
			width := len(str(e.name))
			init := len(str(e.init_string))
			if init != 0 {
				extra := max(name_width-width, 0) + init
				width += extra + 3
			}
			field_width = max(width, field_width)
		}
		return
	}

	write_lead_comment :: proc(using writer: ^Type_Writer, flags: Write_Type_Flags, docs: string, index: int) {
		if docs == "" {
			return
		}
		lines := strings.split_lines(docs)
		defer delete(lines)
		for i := len(lines)-1; i >= 0; i -= 1 {
			if strings.trim_space(lines[i]) == "" {
				lines = lines[:i]
			} else {
				break
			}
		}
		if len(lines) == 0 {
			return
		}
		// if index != 0 { io.write_string(w, "\n") }
		for line in lines {
			do_indent(writer, flags)
			io.write_string(w, "<span class=\"comment\">// ")
			io.write_string(w, line)
			io.write_string(w, "</span>\n")
		}
	}
	write_line_comment :: proc(using writer: ^Type_Writer, flags: Write_Type_Flags, padding: int, comment: string) {
		if comment == "" {
			return
		}
		for _ in 0..< padding {
			io.write_byte(w, ' ')
		}

		io.write_string(w, "<span class=\"comment\">// ")
		io.write_string(w, strings.trim_right_space(comment))
		io.write_string(w, "</span>")
	}


	type_entities := array(type.entities)
	type_types := array(type.types)
	switch type.kind {
	case .Invalid:
		// ignore
	case .Basic:
		type_flags := transmute(doc.Type_Flags_Basic)type.flags
		if is_type_untyped(type) {
			io.write_string(w, str(type.name))
		} else {
			fmt.wprintf(w, `<span class="doc-builtin">%s</span>`, str(type.name))
			// io.write_string(w, str(type.name))
		}
	case .Named:
		e := entities[type_entities[0]]
		name := str(type.name)
		tn_pkg := files[e.pos.file].pkg
		collection: Collection
		if c := pkg_to_collection[&pkgs[tn_pkg]]; c != nil {
			collection = c^
		}

		if tn_pkg != pkg {
			// remove the extra prefix e.g. `foo.foo.bar`
			name_prefix := name
			if n := strings.index_byte(name_prefix, '('); n >= 0 {
				name_prefix = name_prefix[:n]
			}
			if !strings.contains_rune(name_prefix, '.') {
				fmt.wprintf(w, `%s.`, str(pkgs[tn_pkg].name))
			}
		}
		if .Private in e.flags {
			io.write_string(w, name)
		} else if n := strings.index_rune(name, '('); n >= 0 {
			fmt.wprintf(w, `<a class="code-typename" href="{2:s}/{0:s}/#{1:s}">{1:s}</a>`, pkg_to_path[&pkgs[tn_pkg]], name[:n], collection.base_url)
			io.write_string(w, name[n:])
		} else {
			fmt.wprintf(w, `<a class="code-typename" href="{2:s}/{0:s}/#{1:s}">{1:s}</a>`, pkg_to_path[&pkgs[tn_pkg]], name, collection.base_url)
		}
	case .Generic:
		name := str(type.name)
		if name not_in generic_scope {
			io.write_byte(w, '$')
		}
		io.write_string(w, name)
		if name not_in generic_scope && len(array(type.types)) == 1 {
			io.write_byte(w, '/')
			write_type(writer, types[type_types[0]], flags)
		}
	case .Pointer:
		io.write_byte(w, '^')
		write_type(writer, types[type_types[0]], flags)
	case .Array:
		assert(type.elem_count_len == 1)
		io.write_byte(w, '[')
		io.write_uint(w, uint(type.elem_counts[0]))
		io.write_byte(w, ']')
		write_type(writer, types[type_types[0]], flags)
	case .Enumerated_Array:
		io.write_byte(w, '[')
		write_type(writer, types[type_types[0]], flags)
		io.write_byte(w, ']')
		write_type(writer, types[type_types[1]], flags)
	case .Slice:
		if .Variadic in flags {
			io.write_string(w, "..")
		} else {
			io.write_string(w, "[]")
		}
		write_type(writer, types[type_types[0]], flags - {.Variadic})
	case .Dynamic_Array:
		io.write_string(w, "[<span class=\"keyword\">dynamic</span>]")
		write_type(writer, types[type_types[0]], flags)
	case .Map:
		io.write_string(w, "<span class=\"keyword-type\">map</span>[")
		write_type(writer, types[type_types[0]], flags)
		io.write_byte(w, ']')
		write_type(writer, types[type_types[1]], flags)
	case .Struct:
		type_flags := transmute(doc.Type_Flags_Struct)type.flags
		io.write_string(w, "<span class=\"keyword-type\">struct</span>")
		write_poly_params(writer, type, flags)
		if .Packed in type_flags { io.write_string(w, " <span class=\"directive\">#packed</span>") }
		if .Raw_Union in type_flags { io.write_string(w, " <span class=\"directive\">#raw_union</span>") }
		if custom_align := str(type.custom_align); custom_align != "" {
			io.write_string(w, " <span class=\"directive\">#align</span>&nbsp;")
			io.write_string(w, custom_align)
		}
		io.write_string(w, " {")

		tags := array(type.tags)

		if len(type_entities) != 0 {
			do_newline(writer, flags)
			indent += 1
			name_width := calc_name_width(type_entities)

			for entity_index, i in type_entities {
				e := &entities[entity_index]
				next_entity: ^doc.Entity = nil
				if i+1 < len(type_entities) {
					next_entity = &entities[type_entities[i+1]]
				}
				docs, comment := str(e.docs), str(e.comment)

				write_lead_comment(writer, flags, docs, i)

				do_indent(writer, flags)
				write_param_entity(writer, e, next_entity, flags, name_width)

				if tag := str(tags[i]); tag != "" {
					io.write_byte(w, ' ')
					io.write_quoted_string(w, tag)
				}

				io.write_byte(w, ',')
				do_newline(writer, flags)
			}
			indent -= 1
			do_indent(writer, flags)
		}
		io.write_string(w, "}")
	case .Union:
		type_flags := transmute(doc.Type_Flags_Union)type.flags
		io.write_string(w, "<span class=\"keyword-type\">union</span>")
		write_poly_params(writer, type, flags)
		if .No_Nil in type_flags { io.write_string(w, " <span class=\"directive\">#no_nil</span>") }
		if .Maybe in type_flags { io.write_string(w, " <span class=\"directive\">#maybe</span>") }
		if custom_align := str(type.custom_align); custom_align != "" {
			io.write_string(w, " <span class=\"directive\">#align</span>&nbsp;")
			io.write_string(w, custom_align)
		}
		io.write_string(w, " {")
		if len(type_types) > 1 {
			do_newline(writer, flags)
			indent += 1
			for type_index in type_types {
				do_indent(writer, flags)
				write_type(writer, types[type_index], flags)
				io.write_string(w, ", ")
				do_newline(writer, flags)
			}
			indent -= 1
			do_indent(writer, flags)
		}
		io.write_string(w, "}")
	case .Enum:
		io.write_string(w, "<span class=\"keyword-type\">enum</span>")
		if len(type_types) != 0 {
			io.write_byte(w, ' ')
			write_type(writer, types[type_types[0]], flags)
		}
		io.write_string(w, " {")
		do_newline(writer, flags)
		indent += 1

		name_width := calc_name_width(type_entities)
		field_width := calc_field_width(type_entities)

		for entity_index, i in type_entities {
			e := &entities[entity_index]
			docs, comment := str(e.docs), str(e.comment)

			write_lead_comment(writer, flags, docs, i)

			name := str(e.name)
			do_indent(writer, flags)
			io.write_string(w, name)

			init_string := str(e.init_string)
			if init_string != "" {
				for _ in 0..<name_width-len(name) {
					io.write_byte(w, ' ')
				}
				io.write_string(w, " = ")
				io.write_string(w, init_string)
			}
			io.write_string(w, ", ")

			curr_field_width := len(name)
			if init_string != "" {
				curr_field_width += max(name_width-len(name), 0)
				curr_field_width += 3
				curr_field_width += len(init_string)
			}

			write_line_comment(writer, flags, field_width-curr_field_width, comment)

			do_newline(writer, flags)
		}
		indent -= 1
		do_indent(writer, flags)
		io.write_string(w, "}")
	case .Tuple:
		if len(type_entities) == 0 {
			return
		}
		require_parens := (.Is_Results in flags) && (len(type_entities) > 1 || !is_entity_blank(type_entities[0]))
		if require_parens { io.write_byte(w, '(') }
		all_blank := true
		for entity_index, i in type_entities {
			e := &entities[entity_index]
			if name := str(e.name); name == "" || name == "_" {
				if str(e.init_string) != "" {
					all_blank = false
					break
				}
			} else {
				all_blank = false
				break
			}
		}
		span_multiple_lines := false
		if .Allow_Multiple_Lines in flags && .Is_Results not_in flags {
			span_multiple_lines = len(type_entities) >= 6

			if strings.has_prefix(str(pkgs[pkg].name), "objc_") {
				span_multiple_lines = true
			}
		}

		full_name_width :: proc(entity_indices: []doc.Entity_Index) -> (width: int) {
			for entity_index, i in entity_indices {
				if i > 0 {
					width += 2
				}
				width += len(str(entities[entity_index].name))
			}
			return
		}

		if span_multiple_lines {
			max_name_width := 0

			groups: [dynamic][]doc.Entity_Index
			defer delete(groups)

			prev_field_group_index := i32le(-1)
			prev_field_index := 0
			for i := 0; i <= len(type_entities); i += 1 {
				e: ^doc.Entity
				if i != len(type_entities) {
					e = &entities[type_entities[i]]
				}
				if i+1 >= len(type_entities) || prev_field_group_index != e.field_group_index {
					if i != len(type_entities) {
						prev_field_group_index = e.field_group_index
					}
					group := type_entities[prev_field_index:i]
					if len(group) > 0 {
						append(&groups, group)
						width := full_name_width(group)
						max_name_width = max(max_name_width, width)
					}
					prev_field_index = i
				}
			}

			j := 0
			for group, group_idx in groups {
				io.write_string(w, "\n\t")
				group_name_width := full_name_width(group)
				for entity_index, i in group {
					defer j += 1


					e := &entities[entity_index]
					next_entity: ^doc.Entity = nil
					if j+1 < len(type_entities) {
						next_entity = &entities[type_entities[j+1]]
					}

					name_width := 0
					if i+1 == len(group) {
						name_width = max_name_width - group_name_width + len(str(e.name))
					}
					write_param_entity(writer, e, next_entity, flags, name_width)
					io.write_string(w, ", ")
				}
			}

			io.write_string(w, "\n")
		} else {
			for entity_index, i in type_entities {
				e := &entities[entity_index]

				if i > 0 {
					io.write_string(w, ", ")
				}
				next_entity: ^doc.Entity = nil
				if i+1 < len(type_entities) {
					next_entity = &entities[type_entities[i+1]]
				}

				write_param_entity(writer, e, next_entity, flags)
			}
		}
		if require_parens { io.write_byte(w, ')') }

	case .Proc:
		type_flags := transmute(doc.Type_Flags_Proc)type.flags
		io.write_string(w, "<span class=\"keyword-type\">proc</span>")
		cc := str(type.calling_convention)
		switch cc {
		case "odin":
			cc = "" // ignore
		case "cdecl":
			cc = "c"
		}
		if cc != "" {
			io.write_byte(w, ' ')
			io.write_quoted_string(w, cc)
			io.write_byte(w, ' ')
		}
		params := array(type.types)[0]
		results := array(type.types)[1]
		io.write_byte(w, '(')
		write_type(writer, types[params], flags)
		io.write_byte(w, ')')
		if results != 0 {
			assert(.Diverging not_in type_flags)
			io.write_string(w, " -> ")
			write_type(writer, types[results], flags+{.Is_Results})
		}
		if .Diverging in type_flags {
			io.write_string(w, " -> !")
		}
		if .Optional_Ok in type_flags {
			io.write_string(w, " <span class=\"directive\">#optional_ok</span>")
		}

	case .Bit_Set:
		type_flags := transmute(doc.Type_Flags_Bit_Set)type.flags
		io.write_string(w, "<span class=\"keyword-type\">bit_set</span>[")
		if .Op_Lt in type_flags {
			io.write_uint(w, uint(type.elem_counts[0]))
			io.write_string(w, "..<")
			io.write_uint(w, uint(type.elem_counts[1]))
		} else if .Op_Lt_Eq in type_flags {
			io.write_uint(w, uint(type.elem_counts[0]))
			io.write_string(w, "..=")
			io.write_uint(w, uint(type.elem_counts[1]))
		} else {
			write_type(writer, types[type_types[0]], flags)
		}
		if .Underlying_Type in type_flags {
			io.write_string(w, "; ")
			write_type(writer, types[type_types[1]], flags)
		}
		io.write_string(w, "]")
	case .Simd_Vector:
		io.write_string(w, "<span class=\"directive\">#simd</span>[")
		io.write_uint(w, uint(type.elem_counts[0]))
		io.write_byte(w, ']')
	case .SOA_Struct_Fixed:
		io.write_string(w, "<span class=\"directive\">#soa</span>[")
		io.write_uint(w, uint(type.elem_counts[0]))
		io.write_byte(w, ']')
	case .SOA_Struct_Slice:
		io.write_string(w, "<span class=\"directive\">#soa</span>[]")
	case .SOA_Struct_Dynamic:
		io.write_string(w, "<span class=\"directive\">#soa</span>[<span class=\"keyword\">dynamic</span>]")
	case .Soa_Pointer:
		io.write_string(w, "<span class=\"directive\">#soa</span>^")
		if len(type_types) != 0 && len(types) != 0 {
			write_type(writer, types[type_types[0]], flags)
		}
	case .Relative_Pointer:
		io.write_string(w, "<span class=\"directive\">#relative</span>(")
		write_type(writer, types[type_types[1]], flags)
		io.write_string(w, ") ")
		write_type(writer, types[type_types[0]], flags)
	case .Relative_Slice:
		io.write_string(w, "<span class=\"directive\">#relative</span>(")
		write_type(writer, types[type_types[1]], flags)
		io.write_string(w, ") ")
		write_type(writer, types[type_types[0]], flags)
	case .Multi_Pointer:
		io.write_string(w, "[^]")
		write_type(writer, types[type_types[0]], flags)
	case .Matrix:
		io.write_string(w, "<span class=\"keyword-type\">matrix</span>[")
		io.write_uint(w, uint(type.elem_counts[0]))
		io.write_string(w, ", ")
		io.write_uint(w, uint(type.elem_counts[1]))
		io.write_string(w, "]")
		write_type(writer, types[type_types[0]], flags)
	}
}

write_doc_line :: proc(w: io.Writer, text: string) {
	text := text
	for len(text) != 0 {
		if strings.count(text, "`") >= 2 {
			n := strings.index_byte(text, '`')
			io.write_string(w, text[:n])
			io.write_string(w, "<code class=\"code-inline\">")
			remaining := text[n+1:]
			m := strings.index_byte(remaining, '`')
			io.write_string(w, remaining[:m])
			io.write_string(w, "</code>")
			text = remaining[m+1:]
		} else {
			io.write_string(w, text)
			return
		}
	}
}

write_markup_text :: proc(w: io.Writer, s: string) {
	// We need to ensure that we don't escape html tags in our docs
	s, _ := strings.replace_all(s, "<", HTML_LESS_THAN, context.temp_allocator)
	// Consume '- ' if the string begins with one
	// this means we need to make a bullet point
	is_list_element: bool
	if len(s) > 1 && strings.has_prefix(s, "- ") {
		s = strings.trim_left_space(s[2:])
		// NOTE: The reason for a span rather than <li> is that list items cannpt be in a paragraph
		io.write_string(w, "<span class=\"doc-list\">")
		is_list_element = true
	}
	defer if is_list_element do io.write_string(w, "</span>")
	// In markdown 2 spaces at the end a line indicates a break is needed
	need_break: bool
	if len(s) >= 2 && s[len(s) - 2:] == "  " {
		s = s[:len(s) - 2]
		need_break = true
	}
	defer if need_break do io.write_string(w, "<br>")

	latest_index := 0
	for index := 0; index < len(s); index += 1 {
		switch s[index] {
		case '`':
			next_tick := strings.index_byte(s[index + 1:], '`')
			if next_tick >= 0 {
				next_tick += index + 1
				io.write_string(w, s[latest_index:index])
				io.write_string(w, "<code>")
				io.write_string(w, s[index + 1:next_tick])
				io.write_string(w, "</code>")
				latest_index = next_tick + 1
				index = latest_index
			}
		case '*':
			Star_Type :: enum {
				none,
				bold,
				italics,
			}
			star_type := Star_Type.none
			next_star := strings.index_byte(s[index + 1:], '*')
			if next_star == 0 {
				// double star we are bold
				star_type = .bold
			} else if next_star > 0 {
				star_type = .italics
			}
			switch star_type {
			case .bold:
				ending_star := strings.index(s[index + 2:], "**")
				if ending_star < 0 {
					continue
				}
				ending_star += index + 2
				io.write_string(w, s[latest_index:index])
				io.write_string(w, "<b>")
				io.write_string(w, s[index + 2:ending_star])
				io.write_string(w, "</b>")
				latest_index = ending_star + 2
				index = latest_index
			case .italics:
				next_star += index + 1
				io.write_string(w, s[latest_index:index])
				io.write_string(w, "<i>")
				io.write_string(w, s[index + 1:next_star])
				io.write_string(w, "</i>")
				latest_index = next_star + 1
				index = latest_index
			case .none: // nothing
			}
		}
	}
	io.write_string(w, s[latest_index:])
}

write_docs :: proc(w: io.Writer, docs: string, name: string = "") {
	if docs == "" {
		return
	}

	Block_Kind :: enum {
		Paragraph,
		Code,
		Example,
		Output,
	}
	Block :: struct {
		kind: Block_Kind,
		lines: []string,
	}

	lines := strings.split_lines(docs)
	curr_block_kind := Block_Kind.Paragraph
	start := 0
	blocks: [dynamic]Block

	example_block: Block // when set the kind should be Example
	output_block: Block // when set the kind should be Output
	// rely on zii that the kinds have not been set
	assert(example_block.kind != .Example)
	assert(output_block.kind != .Output)

	insert_block :: proc(block: Block, blocks: ^[dynamic]Block, example: ^Block, output: ^Block, name: string) {
		switch block.kind {
		case .Paragraph: fallthrough
		case .Code: append(blocks, block)
		case .Example:
			if example.kind == .Example {
				errorf("The documentation for %q has multiple examples which is not allowed\n", name)
			}
			example^ = block
		case .Output:
			if example.kind == .Output {
				errorf("The documentation for %q has multiple output which is not allowed\n", name)
			}
			output^ = block
		}
	}

	for line, i in lines {
		text := strings.trim_space(line)
		next_block_kind := curr_block_kind
		force_write_block := false

		switch curr_block_kind {
		case .Paragraph:
			switch {
			case strings.has_prefix(line, "Example:"): next_block_kind = .Example
			case strings.has_prefix(line, "Output:"): next_block_kind = .Output
			case strings.has_prefix(line, "\t"): next_block_kind = .Code
			case text == "": force_write_block = true
			}
		case .Code:
			switch {
			case strings.has_prefix(line, "Example:"): next_block_kind = .Example
			case strings.has_prefix(line, "Output:"): next_block_kind = .Output
			case ! (text == "" || strings.has_prefix(line, "\t")): next_block_kind = .Paragraph
			}
		case .Example:
			switch {
			case strings.has_prefix(line, "Output:"): next_block_kind = .Output
			case ! (text == "" || strings.has_prefix(line, "\t")): next_block_kind = .Paragraph
			}
		case .Output:
			switch {
			case strings.has_prefix(line, "Example:"): next_block_kind = .Example
			case ! (text == "" || strings.has_prefix(line, "\t")): next_block_kind = .Paragraph
			}
		}

		if i-start > 0 && (curr_block_kind != next_block_kind || force_write_block) {
			insert_block(Block{curr_block_kind, lines[start:i]}, &blocks, &example_block, &output_block, name)
			curr_block_kind, start = next_block_kind, i
		}
	}

	if start < len(lines) {
		insert_block(Block{curr_block_kind, lines[start:]}, &blocks, &example_block, &output_block, name)
	}

	if output_block.kind == .Output && example_block.kind != .Example {
		errorf("The documentation for %q has an output block but no example\n", name)
	}

	for block in &blocks {
		trim_amount := 0
		for trim_amount = 0; trim_amount < len(block.lines); trim_amount += 1 {
			line := block.lines[trim_amount]
			if strings.trim_space(line) != "" {
				break
			}
		}
		block.lines = block.lines[trim_amount:]
	}

	for block, i in blocks {
		if len(block.lines) == 0 {
			continue
		}
		prev_line := ""
		if i > 0 {
			prev_lines := blocks[i-1].lines
			if len(prev_lines) > 0 {
				prev_line = prev_lines[len(prev_lines)-1]
			}
		}
		prev_line = strings.trim_space(prev_line)

		lines := block.lines[:]

		switch block.kind {
		case .Paragraph:
			io.write_string(w, "<p>")

			subtitles_to_markup := [?]string{ "Inputs:", "Returns:" }
			for subtitle in subtitles_to_markup {
				if ! strings.has_prefix(lines[0], subtitle) {
					continue
				}
				fmt.wprintf(w, "<b>%v</b><br>", subtitle)
				removed_subtitle := strings.trim_prefix(lines[0], subtitle)
				removed_subtitle = strings.trim_left_space(removed_subtitle)
				if removed_subtitle == "" {
					lines = lines[1:]
				} else {
					lines[0] = removed_subtitle
				}
				break
			}

			for line, line_idx in lines {
				if line_idx > 0 {
					io.write_string(w, "\n")
				}
				write_markup_text(w, line)
			}
			io.write_string(w, "</p>\n")
		case .Code:
			all_blank := len(lines) > 0
			for line in lines {
				if strings.trim_space(line) != "" {
					all_blank = false
				}
			}
			if all_blank {
				continue
			}

			io.write_string(w, "<pre>")
			for line in lines {
				trimmed := strings.trim_prefix(line, "\t")
				s, _ := strings.replace_all(trimmed, "<", HTML_LESS_THAN, context.temp_allocator)
				io.write_string(w, s)
				io.write_string(w, "\n")
			}
			io.write_string(w, "</pre>\n")
		case .Example: panic("We should not have example blocks in the block array")
		case .Output: panic("We should not have output blocks in the block array")
		}
	}

	// Write example and output block if required
	if example_block.kind == .Example {
		trim_empty_and_subtitle_lines_and_replace_lt :: proc(lines: []string, subtitle: string) -> []string {
			lines := lines
			for len(lines) > 0 && (strings.trim_space(lines[0]) == "" || strings.has_prefix(lines[0], subtitle)) {
				lines = lines[1:]
			}
			for len(lines) > 0 && (strings.trim_space(lines[len(lines) - 1]) == "") {
				lines = lines[:len(lines) - 1]
			}
			for line in &lines {
				line, _ = strings.replace_all(line, "<", HTML_LESS_THAN, context.temp_allocator)
			}
			return lines
		}
		// Example block starts with `Example:` and a number of white spaces,
		example_lines := trim_empty_and_subtitle_lines_and_replace_lt(example_block.lines, "Example:")

		io.write_string(w, "<details open class=\"code-example\">\n")
		defer io.write_string(w, "</details>\n")
		io.write_string(w, "<summary><b>Example:</b></summary>\n")
		io.write_string(w, `<pre><code class="hljs" data-lang="odin">`)
		for line in example_lines {
			io.write_string(w, strings.trim_prefix(line, "\t"))
			io.write_string(w, "\n")
		}
		io.write_string(w, "</code></pre>\n")

		// Add the output block if it is present
		if output_block.kind == .Output {
			// Output block starts with `Output:` and a number of white spaces,
			output_lines := trim_empty_and_subtitle_lines_and_replace_lt(output_block.lines, "Output:")

			io.write_string(w, "<b>Output:</b>\n")
			io.write_string(w, `<pre class="doc-code">`)
			for line in output_lines {
				io.write_string(w, strings.trim_prefix(line, "\t"))
				io.write_string(w, "\n")
			}
			io.write_string(w, "</pre>\n")
		}
	}
}

write_pkg_sidebar :: proc(w: io.Writer, curr_pkg: ^doc.Pkg, collection: ^Collection) {

	fmt.wprintln(w, `<nav id="pkg-sidebar" class="col-lg-2 odin-sidebar-border navbar-light sticky-top odin-below-navbar">`)
	defer fmt.wprintln(w, `</nav>`)
	fmt.wprintln(w, `<div class="py-3">`)
	defer fmt.wprintln(w, `</div>`)

	fmt.wprintf(w, "<h4 style=\"text-transform: capitalize\">%s Library</h4>\n", collection.name)

	fmt.wprintln(w, `<ul>`)
	defer fmt.wprintln(w, `</ul>`)

	for dir in collection.root.children {
		fmt.wprint(w, `<li class="nav-item">`)
		defer fmt.wprintln(w, `</li>`)
		if dir.pkg == curr_pkg {
			fmt.wprintf(w, `<a class="active" href="%s/%s">%s</a>`, collection.base_url, dir.path, dir.name)
		} else if dir.pkg != nil {
			fmt.wprintf(w, `<a href="%s/%s">%s</a>`, collection.base_url, dir.path, dir.name)
		} else {
			fmt.wprintf(w, "%s", dir.name)
		}
		if len(dir.children) != 0 {
			fmt.wprintln(w, "<ul>")
			defer fmt.wprintln(w, "</ul>\n")
			for child in dir.children {
				fmt.wprint(w, `<li>`)
				defer fmt.wprintln(w, `</li>`)
				if child.pkg == curr_pkg {
					fmt.wprintf(w, `<a class="active" href="%s/%s">%s</a>`, collection.base_url, child.path, child.name)
				} else if child.pkg != nil {
					fmt.wprintf(w, `<a href="%s/%s">%s</a>`, collection.base_url, child.path, child.name)
				} else {
					fmt.wprintf(w, "%s", child.name)
				}
			}
		}
	}
}

write_breadcrumbs :: proc(w: io.Writer, path: string, pkg: ^doc.Pkg, collection: ^Collection) {
	fmt.wprintln(w, `<nav class="pkg-breadcrumb" aria-label="breadcrumb">`)
	defer fmt.wprintln(w, `</nav>`)

	dirs := strings.split(path, "/")
	defer delete(dirs)

	io.write_string(w, "<ol class=\"breadcrumb\">\n")
	fmt.wprintf(w, "<li class=\"breadcrumb-item\"><a href=\"%s\">%s</a></li>\n", collection.base_url, strings.to_lower(collection.name, context.temp_allocator))
	for dir, i in dirs {
		is_active_string := ""
		if i+1 == len(dirs) {
			is_active_string = ` active" aria-current="page`
		}

		trimmed_path := strings.join(dirs[:i+1], "/", context.temp_allocator)
		if _, ok := collection.pkgs_to_use[trimmed_path]; ok {
			fmt.wprintf(w, "<li class=\"breadcrumb-item%s\"><a href=\"%s/%s\">%s</a></li>\n", is_active_string, collection.base_url, trimmed_path, dir)
		} else {
			fmt.wprintf(w, "<li class=\"breadcrumb-item\">%s</li>\n", dir)
		}
	}
	io.write_string(w, "</ol>\n")
}

find_entity_attribute :: proc(e: ^doc.Entity, key: string) -> (value: string, ok: bool) {
	for attr in array(e.attributes) {
		if str(attr.name) == key {
			return str(attr.value), true
		}
	}
	return
}


Pkg_Entries :: struct {
	procs:       [dynamic]doc.Scope_Entry,
	proc_groups: [dynamic]doc.Scope_Entry,
	types:       [dynamic]doc.Scope_Entry,
	vars:        [dynamic]doc.Scope_Entry,
	consts:      [dynamic]doc.Scope_Entry,

	all:         [dynamic]doc.Scope_Entry,

	ordering: [5]struct{name: string, entries: []doc.Scope_Entry},
}

pkg_entries_gather :: proc(pkg: ^doc.Pkg) -> (entries: Pkg_Entries) {
	for entry in array(pkg.entries) {
		e := &entities[entry.entity]
		name := str(e.name)
		if name == "" || name[0] == '_' {
			continue
		}
		name = str(entry.name)
		if name == "" || name[0] == '_' {
			continue
		}
		switch e.kind {
		case .Invalid, .Import_Name, .Library_Name:
			continue
		case .Constant:
			append(&entries.consts, entry)
		case .Variable:
			append(&entries.vars, entry)
		case .Type_Name:
			append(&entries.types, entry)
		case .Procedure:
			append(&entries.procs, entry)
		case .Builtin:
			append(&entries.procs, entry)
		case .Proc_Group:
			append(&entries.proc_groups, entry)
		}
		append(&entries.all, entry)
	}

	entity_key :: proc(entry: doc.Scope_Entry) -> string {
		return str(entry.name)
	}

	slice.sort_by_key(entries.procs[:],       entity_key)
	slice.sort_by_key(entries.proc_groups[:], entity_key)
	slice.sort_by_key(entries.types[:],       entity_key)
	slice.sort_by_key(entries.vars[:],        entity_key)
	slice.sort_by_key(entries.consts[:],      entity_key)
	slice.sort_by_key(entries.all[:],         entity_key)

	entries.ordering = {
		{"Types",            entries.types[:]},
		{"Constants",        entries.consts[:]},
		{"Variables",        entries.vars[:]},
		{"Procedures",       entries.procs[:]},
		{"Procedure Groups", entries.proc_groups[:]},
	}
	return
}

pkg_entries_destroy :: proc(entries: ^Pkg_Entries) {
	delete(entries.procs)
	delete(entries.proc_groups)
	delete(entries.types)
	delete(entries.vars)
	delete(entries.consts)
	entries^ = {}
}

write_search :: proc(w: io.Writer, kind: enum { Package, Collection, All}) {
	class := ""
	switch kind {
	case .Package:    class = "odin-search-package"
	case .Collection: class = "odin-search-collection"
	case .All:        class = "odin-search-all"
	}
	fmt.wprintf(w, `<input type="search" id="odin-search" class="%s" autocomplete="off" spellcheck="false" placeholder="Fuzzy Search...">`, class)
	fmt.wprintln(w)

	switch kind {
	case .Package:
		// ignore
	case .Collection, .All:
		fmt.wprintln(w, `<ul id="odin-search-results"></ul>`)
	}
}


write_pkg :: proc(w: io.Writer, dir, path: string, pkg: ^doc.Pkg, collection: ^Collection, pkg_entries: Pkg_Entries) {
	fmt.wprintln(w, `<div class="row odin-main" id="pkg">`)
	defer fmt.wprintln(w, `</div>`)

	write_pkg_sidebar(w, pkg, collection)

	fmt.wprintln(w, `<article class="col-lg-8 p-4 documentation odin-article">`)

	write_breadcrumbs(w, path, pkg, collection)

	fmt.wprintf(w, "<h1>package %s:%s", strings.to_lower(collection.name, context.temp_allocator), path)

	pkg_src_url := fmt.tprintf("%s/%s", collection.github_url, path)
	fmt.wprintf(w, "<div class=\"doc-source\"><a href=\"{0:s}\"><em>Source</em></a></div>", pkg_src_url)
	fmt.wprintf(w, "</h1>\n")

	path_url := fmt.tprintf("%s/%s", dir, path)
	write_search(w, .Package)

	// // TODO(bill): determine decent approach for performance
	// if len(array(pkg.entries)) <= 1000 {
	// 	io.write_string(w, `<div class="input-group">`)
	// 	io.write_string(w, `<input type="text" id="pkg-fuzzy-search" class="form-control" placeholder="Search Docs...">`+"\n")
	// 	io.write_string(w, `</div>`+"\n")
	// }

	fmt.wprintln(w, `<div id="pkg-top">`)

	overview_docs := strings.trim_space(str(pkg.docs))
	if overview_docs != "" {
		fmt.wprintln(w, "<h2>Overview</h2>")
		fmt.wprintln(w, "<div id=\"pkg-overview\">")
		defer fmt.wprintln(w, "</div>")

		write_docs(w, overview_docs)
	}

	fmt.wprintln(w, `<div id="pkg-index">`)
	fmt.wprintln(w, `<h2>Index</h2>`)


	write_index :: proc(w: io.Writer, name: string, entries: []doc.Scope_Entry) {
		fmt.wprintln(w, `<div>`)
		defer fmt.wprintln(w, `</div>`)


		fmt.wprintf(w, `<details class="doc-index" id="doc-index-{0:s}" aria-labelledby="#doc-index-{0:s}-header">`+"\n", name)
		fmt.wprintf(w, `<summary id="#doc-index-{0:s}-header">`+"\n", name)
		io.write_string(w, name)
		io.write_string(w, " (")
		io.write_int(w, len(entries))
		io.write_string(w, ")")
		fmt.wprintln(w, `</summary>`)
		defer fmt.wprintln(w, `</details>`)

		if len(entries) == 0 {
			io.write_string(w, "<p class=\"pkg-empty-section\">This section is empty.</p>\n")
		} else {
			fmt.wprintln(w, "<ul>")
			for e in entries {
				name := str(e.name)
				fmt.wprintf(w, "<li><a href=\"#{0:s}\">{0:s}</a></li>\n", name)
			}
			fmt.wprintln(w, "</ul>")
		}
	}

	for eo in pkg_entries.ordering {
		write_index(w, eo.name, eo.entries)
	}

	fmt.wprintln(w, "</div>")
	fmt.wprintln(w, "</div>")


	write_entry :: proc(w: io.Writer, pkg: ^doc.Pkg, entry: doc.Scope_Entry) {
		write_attributes :: proc(w: io.Writer, e: ^doc.Entity) {
			for attr in array(e.attributes) {
				io.write_string(w, "@(")
				name := str(attr.name)
				value := str(attr.value)
				io.write_string(w, name)
				if value != "" {
					io.write_string(w, "=")
					io.write_string(w, value)
				}
				io.write_string(w, ")\n")
			}
		}

		write_entity_reference :: proc(w: io.Writer, pkg: ^doc.Pkg, entity: ^doc.Entity) {
			name := str(entity.name)

			this_pkg := &pkgs[files[entity.pos.file].pkg]
			if .Builtin_Pkg_Builtin in entity.flags {
				fmt.wprintf(w, "builtin.%s", name)
				return
			} else if .Builtin_Pkg_Intrinsics in entity.flags {
				fmt.wprintf(w, "intrinsics.%s", name)
				return
			} else if pkg != this_pkg {
				fmt.wprintf(w, "%s.", str(this_pkg.name))
			}
			collection := pkg_to_collection[this_pkg]

			class := ""
			if entity.kind == .Procedure {
				class = "code-procedure"
			}

			fmt.wprintf(w, `<a class="{3:s}" href="{2:s}/{0:s}/#{1:s}">`, pkg_to_path[this_pkg], name, collection.base_url, class)
			io.write_string(w, name)
			io.write_string(w, `</a>`)
		}

		name := str(entry.name)
		e := &entities[entry.entity]
		entity_name := str(e.name)


		entity_pkg_index := files[e.pos.file].pkg
		entity_pkg := &pkgs[entity_pkg_index]
		writer := &Type_Writer{
			w = w,
			pkg = doc.Pkg_Index(intrinsics.ptr_sub(pkg, &pkgs[0])),
		}
		defer delete(writer.generic_scope)
		collection := pkg_to_collection[pkg]
		github_url := collection.github_url if collection != nil else GITHUB_CORE_URL

		path := pkg_to_path[pkg]
		filename := slashpath.base(str(files[e.pos.file].name))
		fmt.wprintf(w, "<h3 id=\"{0:s}\"><span><a class=\"doc-id-link\" href=\"#{0:s}\">{0:s}", name)
		fmt.wprintf(w, "<span class=\"a-hidden\">&nbsp;¶</span></a></span>")
		if e.pos.file != 0 && e.pos.line > 0 {
			src_url := fmt.tprintf("%s/%s/%s#L%d", github_url, path, filename, e.pos.line)
			fmt.wprintf(w, "<div class=\"doc-source\"><a href=\"{0:s}\"><em>Source</em></a></div>", src_url)
		}
		fmt.wprintf(w, "</h3>\n")
		fmt.wprintln(w, `<div>`)

		if name != entity_name || entity_pkg != pkg {
			fmt.wprint(w, `<pre class="doc-code">`)
			fmt.wprintf(w, "%s :: ", name)
			write_entity_reference(w, pkg, e)
			fmt.wprintln(w, "</pre>")
		} else {
			switch e.kind {
			case .Invalid, .Import_Name, .Library_Name:
				// ignore
			case .Constant:
				fmt.wprint(w, `<pre class="doc-code">`)
				the_type := types[e.type]

				init_string := str(e.init_string)
				assert(init_string != "")

				ignore_type := true
				if the_type.kind == .Basic && is_type_untyped(the_type) {
				} else {
					ignore_type = false
					type_name := str(the_type.name)
					if type_name != "" && strings.has_prefix(init_string, type_name) {
						ignore_type = true
					}
				}

				if ignore_type {
					fmt.wprintf(w, "%s :: ", name)
				} else {
					fmt.wprintf(w, "%s: ", name)
					write_type(writer, the_type, {.Allow_Indent})
					fmt.wprintf(w, " : ")
				}


				io.write_string(w, init_string)
				fmt.wprintln(w, "</pre>")
			case .Variable:
				fmt.wprint(w, `<pre class="doc-code">`)
				write_attributes(w, e)
				fmt.wprintf(w, "%s: ", name)
				write_type(writer, types[e.type], {.Allow_Indent})
				init_string := str(e.init_string)
				if init_string != "" {
					io.write_string(w, " = ")
					io.write_string(w, "…")
				}
				fmt.wprintln(w, "</pre>")

			case .Type_Name:
				fmt.wprint(w, `<pre class="doc-code">`)
				defer fmt.wprintln(w, "</pre>")

				write_attributes(w, e)
				fmt.wprintf(w, "%s :: ", name)
				the_type := types[e.type]
				type_to_print := the_type
				if base_type(type_to_print).kind == .Basic && str(pkg.name) == "c" {
					io.write_string(w, str(e.init_string))
					break
				}

				if the_type.kind == .Named && .Type_Alias not_in e.flags {
					if e.pos == entities[array(the_type.entities)[0]].pos {
						bt := base_type(the_type)
						#partial switch bt.kind {
						case .Struct, .Union, .Proc, .Enum:
							// Okay
						case:
							io.write_string(w, "distinct ")
						}
						type_to_print = bt
					}
				}
				write_type(writer, type_to_print, {.Allow_Indent})
			case .Builtin:
				fmt.wprint(w, `<pre class="doc-code">`)
				fmt.wprintf(w, "%s :: ", name)
				write_entity_reference(w, pkg, e)
				fmt.wprint(w, `</pre>`)
			case .Procedure:
				fmt.wprint(w, `<pre class="doc-code">`)
				fmt.wprintf(w, "%s :: ", name)
				write_type(writer, types[e.type], {.Allow_Multiple_Lines})
				write_where_clauses(w, array(e.where_clauses))
				if .Foreign in e.flags {
					fmt.wprint(w, " ---")
				} else {
					fmt.wprint(w, " {…}")
				}
				fmt.wprintln(w, "</pre>")

				write_objc_method_info(writer, pkg, e)

			case .Proc_Group:
				fmt.wprint(w, `<pre class="doc-code">`)
				fmt.wprintf(w, "%s :: proc{{\n", name)
				for entity_index in array(e.grouped_entities) {
					this_proc := &entities[entity_index]
					io.write_byte(w, '\t')
					write_entity_reference(w, pkg, this_proc)
					io.write_byte(w, ',')
					io.write_byte(w, '\n')
				}
				fmt.wprintln(w, "}")
				fmt.wprintln(w, "</pre>")

				write_objc_method_info(writer, pkg, e)
			}
		}
		fmt.wprintln(w, `</div>`)

		the_docs := strings.trim_space(str(e.docs))
		if the_docs == "" {
			the_docs = strings.trim_space(str(e.comment))
		}
		if the_docs != "" {
			fmt.wprintln(w, `<details class="odin-doc-toggle" open>`)
			fmt.wprintln(w, `<summary class="hideme"><span>&nbsp;</span></summary>`)
			write_docs(w, the_docs, str(e.name))
			fmt.wprintln(w, `</details>`)
		}


		if raw_cls_name, ok := find_entity_attribute(e, "objc_class"); ok {
			cls_name, allocated, cls_name_ok := strconv.unquote_string(raw_cls_name)
			defer if allocated { delete(cls_name) }
			assert(cls_name_ok)

			fmt.wprintln(w, `<div>`)
			defer fmt.wprintln(w, `</div>`)

			method_names_seen: map[string]bool
			write_objc_methods(w, pkg, e, &method_names_seen)
			delete(method_names_seen)

			switch str(pkg.name) {
			case "objc_Metal":
				fmt.wprintf(w, `<em>Apple's Metal Documentation: <a href="https://developer.apple.com/documentation/metal/%s?language=objc">%s</a></em>`, cls_name, cls_name)
			}

		}
	}
	write_entries :: proc(w: io.Writer, pkg: ^doc.Pkg, title: string, entries: []doc.Scope_Entry) {
		fmt.wprintf(w, "<h2 id=\"pkg-{0:s}\" class=\"pkg-header\">{0:s}</h2>\n", title)
		if len(entries) == 0 {
			io.write_string(w, "<p class=\"pkg-empty-section\">This section is empty.</p>\n")
		} else {
			for e in entries {
				fmt.wprintln(w, `<div class="pkg-entity">`)
				write_entry(w, pkg, e)
				fmt.wprintln(w, `</div>`)
			}
		}
	}

	write_objc_method_info :: proc(writer: ^Type_Writer, pkg: ^doc.Pkg, e: ^doc.Entity) -> bool {
		w := writer.w

		objc_name := find_entity_attribute(e, "objc_name") or_return
		objc_type := find_entity_attribute(e, "objc_type") or_return
		objc_name, _ = strconv.unquote_string(objc_name)   or_return

		objc_is_class_method, _ := find_entity_attribute(e, "objc_is_class_method")
		is_class_method := objc_is_class_method == "true"

		parent: ^doc.Entity
		for entry in array(pkg.entries) {
			e := &entities[entry.entity]
			if e.kind == .Type_Name && str(e.name) == objc_type {
				parent = e
				break
			}
		}
		if parent == nil {
			return false
		}

		fmt.wprintln(w, `<div>`)

		fmt.wprintln(w, `<h5>Objective-C Method Information</h5>`)
		fmt.wprintln(w, `<ul>`)
		fmt.wprintf(w, `<li>Class: <a href="#%s">%s</a></li>`+"\n", objc_type, objc_type)
		fmt.wprintf(w, `<li>Name: <strong>%s</strong></li>`+"\n", objc_name)
		if is_class_method {
			fmt.wprintf(w, `<li>Kind: <em>Class Method</em></li>`+"\n")
		}
		fmt.wprintln(w, `</ul>`)
		fmt.wprintln(w, `</div>`)

		fmt.wprintln(w, "<h5>Syntax Usage</h5>")
		fmt.wprintln(w, "<pre>")

		write_syntax_usage :: proc(w: io.Writer, e: ^doc.Entity, objc_name: string, parent: ^doc.Entity, is_class_method: bool) {
			assert(e.kind == .Procedure)
			pt := base_type(types[e.type])
			pentities: []doc.Entity_Index
			rentities: []doc.Entity_Index

			params := &types[array(pt.types)[0]]
			if params.kind == .Tuple {
				pentities = array(params.entities)
				if !is_class_method {
					pentities = pentities[1:]
				}
			}

			results := &types[array(pt.types)[1]]
			if results.kind == .Tuple {
				rentities = array(results.entities)
			}

			if len(rentities) != 0 {
				for e_idx, i in rentities {
					if i != 0 {
						fmt.wprintf(w, ", ")
					}
					e := &entities[e_idx]
					name := str(e.name)
					if name != "" {
						fmt.wprintf(w, "%s", name)
					} else {
						if len(rentities) == 1 {
							fmt.wprintf(w, "res")
						} else {
							fmt.wprintf(w, "res%d", i)
						}
					}
				}
				fmt.wprintf(w, " := ")
			}

			if is_class_method {
				fmt.wprintf(w, `<a href="#{0:s}">{0:s}</a>.`, str(parent.name))
			} else {
				fmt.wprintf(w, "self->")
			}

			fmt.wprintf(w, `<a href="#{0:s}">{1:s}</a>(`, str(e.name), objc_name)
			if len(pentities) > 1 {
				fmt.wprintf(w, "\n")
				for e_idx, i in pentities {
					e := &entities[e_idx]
					fmt.wprintf(w, "\t%s,\n", str(e.name))
				}
			} else {
				for e_idx, i in pentities {
					if i != 0 {
						fmt.wprintf(w, ", ")
					}
					e := &entities[e_idx]
					fmt.wprintf(w, "%s", str(e.name))
				}
			}
			fmt.wprintf(w, ")\n")
		}

		#partial switch e.kind {
		case .Procedure:
			write_syntax_usage(w, e, objc_name, parent, is_class_method)
		case .Proc_Group:
			for e_idx in array(e.grouped_entities) {
				e := &entities[e_idx]
				write_syntax_usage(w, e, objc_name, parent, is_class_method)
			}
		}

		fmt.wprintln(w, "</pre>")
		return true
	}

	write_objc_methods :: proc(w: io.Writer, pkg: ^doc.Pkg, parent: ^doc.Entity, method_names_seen: ^map[string]bool, is_inherited := false) {
		methods: [dynamic]^doc.Entity

		parent_name := str(parent.name)

		for entry in array(pkg.entries) {
			e := &entities[entry.entity]
			if e.kind == .Proc_Group {
				if type_name, ok := find_entity_attribute(e, "objc_type"); ok && parent_name == type_name {
					append(&methods, e)
				}
			}
		}
		for entry in array(pkg.entries) {
			e := &entities[entry.entity]
			if e.kind == .Procedure {
				if type_name, ok := find_entity_attribute(e, "objc_type"); ok && parent_name == type_name {
					append(&methods, e)
				}
			}
		}

		seen_item := false

		loop: for e in methods {
			method_name := find_entity_attribute(e, "objc_name") or_else panic("unable to find objc_name")
			method_name, _ = strconv.unquote_string(method_name) or_else panic("unable to unquote method name")

			if method_names_seen[method_name] {
				continue loop
			}
			method_names_seen[method_name] = true
			if !seen_item {
				if is_inherited {
					fmt.wprintf(w, `<h6>Methods Inherited From <a href="%s/%s/#%s">%s</a></h6>`, pkg_to_collection[pkg].base_url, pkg_to_path[pkg], parent_name, parent_name)
					fmt.wprintln(w)
				} else {
					fmt.wprintln(w, "<h5>Bound Objective-C Methods</h5>")
				}
				fmt.wprintln(w, "<ul>")
				seen_item = true
			}

			fmt.wprintf(w, "<li>")
			fmt.wprintf(w, `<a href="%s/%s/#%s">%s</a>`, pkg_to_collection[pkg].base_url, pkg_to_path[pkg], str(e.name), method_name)

			if v, ok := find_entity_attribute(e, "objc_is_class_method"); ok && v == "true" {
				fmt.wprintf(w, `&nbsp;<em>(class method)</em>`)
			}
			if e.kind == .Proc_Group {
				fmt.wprintf(w, `&nbsp;<em>(overloaded method)</em>`)
			}

			fmt.wprintf(w, "</li>")

			fmt.wprintln(w)
		}

		if seen_item {
			fmt.wprintln(w, "</ul>")
		}

		delete(methods)

		recursive_inheritance_check: {
			parent_type := base_type(types[parent.type])
			assert(parent_type.kind == .Struct)
			fields := array(parent_type.entities)
			for field_idx := len(fields)-1; field_idx >= 0; field_idx -= 1 {
				field := &entities[fields[field_idx]]
				if .Param_Using in field.flags {
					field_type := types[field.type]
					field_type_entity := &entities[array(field_type.entities)[0]]
					field_pkg := &pkgs[files[field.pos.file].pkg]
					write_objc_methods(w, field_pkg, field_type_entity, method_names_seen, true)
				}
			}
		}
	}

	fmt.wprintln(w, `<section class="documentation">`)
	for eo in pkg_entries.ordering {
		write_entries(w, pkg, eo.name, eo.entries)
	}
	fmt.wprintln(w, "</section>")

	fmt.wprintln(w, `<h2 id="pkg-source-files">Source Files</h2>`)
	fmt.wprintln(w, "<ul>")
	any_hidden := false
	source_file_loop: for file_index in array(pkg.files) {
		file := files[file_index]
		filename := slashpath.base(str(file.name))
		switch {
		case
			strings.has_suffix(filename, "_windows.odin"),
			strings.has_suffix(filename, "_darwin.odin"),
			strings.has_suffix(filename, "_essence.odin"),
			strings.has_suffix(filename, "_freebsd.odin"),
			strings.has_suffix(filename, "_wasi.odin"),
			strings.has_suffix(filename, "_js.odin"),
			strings.has_suffix(filename, "_freestanding.odin"),

			strings.has_suffix(filename, "_amd64.odin"),
			strings.has_suffix(filename, "_i386.odin"),
			strings.has_suffix(filename, "_arch64.odin"),
			strings.has_suffix(filename, "_wasm32.odin"),
			strings.has_suffix(filename, "_wasm64.odin"),
			false:
			any_hidden = true
			continue source_file_loop
		}
		fmt.wprintf(w, `<li><a href="%s/%s/%s">%s</a></li>`, collection.github_url, path, filename, filename)
		fmt.wprintln(w)
	}
	if any_hidden {
		fmt.wprintln(w, "<li><em>(hidden platform specific files)</em></li>")
	}
	fmt.wprintln(w, "</ul>")

	{
		fmt.wprintln(w, `<h2 id="pkg-generation-information">Generation Information</h2>`)
		now := time.now()
		fmt.wprintf(w, "<p>Generated with <code>odin version %s (vendor %q) %s_%s @ %v</code></p>\n", ODIN_VERSION, ODIN_VENDOR, ODIN_OS, ODIN_ARCH, now)
	}



	fmt.wprintln(w, `</article>`)
	{
		write_link :: proc(w: io.Writer, id, text: string) {
			fmt.wprintf(w, `<li><a href="#%s">%s</a>`, id, text)
		}

		fmt.wprintln(w, `<div class="col-lg-2 odin-toc-border navbar-light"><div class="sticky-top odin-below-navbar py-3">`)
		fmt.wprintln(w, `<nav id="TableOfContents">`)
		fmt.wprintln(w, `<ul>`)
		if overview_docs != "" {
			write_link(w, "pkg-overview", "Overview")
		}
		for eo in pkg_entries.ordering do if len(eo.entries) != 0 {
			fmt.wprintf(w, `<li><a href="#pkg-{0:s}">{0:s}</a>`, eo.name)
			fmt.wprintln(w, `<ul>`)
			for e in eo.entries {
				fmt.wprintf(w, "<li><a href=\"#{0:s}\">{0:s}</a></li>\n", str(e.name))
			}
			fmt.wprintln(w, "</ul>")
			fmt.wprintln(w, "</li>")
		}
		write_link(w, "pkg-source-files", "Source Files")
		fmt.wprintln(w, `</ul>`)
		fmt.wprintln(w, `</nav>`)
		fmt.wprintln(w, `</div></div>`)
	}

	fmt.wprintf(w, `<script type="text/javascript">var odin_pkg_name = "%s";</script>`+"\n", str(pkg.name))

}
