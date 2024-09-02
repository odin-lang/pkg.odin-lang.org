package odin_html_docs

import "base:intrinsics"
import "core:fmt"
import "core:io"
import "core:log"
import "core:os"
import "core:path/slashpath"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

import doc "core:odin/doc-format"

import cm "vendor:commonmark"

cfg: Config

main :: proc() {
	context.logger = log.create_console_logger(.Debug when ODIN_DEBUG else .Info)

	if len(os.args) < 2 || os.args[1] == "-h" || os.args[1] == "--help" {
		print_usage()
	}

	{
		cfg = config_default()

		if len(os.args) > 2 {
			last_arg := os.args[len(os.args)-1]
			if strings.has_suffix(last_arg, ".json") {
				file_ok, json_err := config_merge_from_file(&cfg, last_arg)
				if !file_ok {
					errorf("unable to read config file at: %s", last_arg)
				}
				if json_err != nil {
					errorf(
						"unable to decode the JSON inside the config file at: %s, error: %v",
						last_arg,
						json_err,
					)
				}
			}
		}

		if len(cfg.collections) == 0 {
			errorf("there must be collections defined in the config")
		}

		for c in cfg.collections {
			if err, has_err := collection_validate(c).?; has_err {
				errorf(err)
			}
		}
	}

	not_hidden: [dynamic]^Collection

	generate_from_path(os.args[1], true)

	if len(os.args) >= 3 && os.args[2] == "--merge" {
		for arg in os.args[3:] {
			strings.has_suffix(arg, ".odin-doc") or_continue
			generate_from_path(arg, false)
		}
	}


	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	w := strings.to_writer(&b)


	for c in cfg.collections {
		if cfg.hide_core && (c.name == "core" || c.name == "vendor") {
			log.infof(
				"'core' is set to be hidden so collection %q will be excluded from search results",
				c.name,
			)
			continue
		}
		if cfg.hide_base && (c.name == "base") {
			log.infof(
				"'base' is set to be hidden so collection %q will be excluded from search results",
				c.name,
			)
			continue
		}

		found := false
		for other in not_hidden {
			if other.name == c.name {
				found = true
				break
			}
		}
		if !found {
			append(&not_hidden, c)
		}
	}

	for collection in not_hidden {
		dir := collection.name

		strings.builder_reset(&b)
		write_html_header(w, fmt.tprintf("%s library - pkg.odin-lang.org", dir))
		write_collection_directory(w, collection)
		write_html_footer(w, true)
		os.make_directory(dir, DIRECTORY_MODE)
		os.write_entire_file(fmt.tprintf("%s/index.html", dir), b.buf[:])

		generate_packages_in_collection(&b, collection)
	}


	{

		strings.builder_reset(&b)
		write_html_header(w, "Packages - pkg.odin-lang.org")
		write_home_page(w)
		write_html_footer(w, true)
		os.write_entire_file("index.html", b.buf[:])
	}


	log.infof("generate json pkg data")
	generate_json_pkg_data(&b, not_hidden[:])

	log.infof("copy_assets")
	copy_assets()

	log.infof("[DONE]")
}

init_cfg_from_header :: proc(header: ^doc.Header, loc := #caller_location) {
	assert(header != nil, loc=loc)
	cfg.header   = header
	cfg.files    = array(cfg.header.files)
	cfg.pkgs     = array(cfg.header.pkgs)
	cfg.entities = array(cfg.header.entities)
	cfg.types    = array(cfg.header.types)
}
init_cfg_from_pkg :: proc(pkg: ^doc.Pkg, loc := #caller_location) {
	assert(pkg != nil, loc=loc)
	init_cfg_from_header(cfg.pkg_to_header[pkg], loc)
}


generate_from_path :: proc(path: string, all_packages: bool) {
	{
		data, ok := os.read_entire_file(path)
		if !ok {
			errorf("unable to read Odin doc file at: %s", path)
		}

		header, err := doc.read_from_bytes(data)
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

		init_cfg_from_header(header)

	}

	when ODIN_DEBUG {
		for c in cfg.collections {
			log.debugf(`Collection %q configured with:
	Source URL: %s
	Base URL: %s
	Root Path: %s
	License: %s at %s
	Hidden: %v
	Home:
		Title: %s
		Description: %s
		Readme: %s`,
				c.name,
				c.source_url,
				c.base_url,
				c.root_path,
				c.license.text,
				c.license.url,
				c.hidden,
				c.home.title,
				c.home.description,
				c.home.embed_readme,
			)
		}
	}

	// Based on paths, assign packages to collections, maybe ignore them.
	{
		pkgs: [dynamic]^doc.Pkg
		defer delete(pkgs)

		for &pkg in cfg.pkgs[1:] {
			fp := str(pkg.fullpath)
			if fp in cfg.handled_packages {
				continue
			}
			append(&pkgs, &pkg)
			cfg.handled_packages[fp] = {}
			cfg.pkg_to_header[&pkg] = cfg.header
		}

		log.infof("%d packages - %s", len(pkgs), path)

		fullpath_loop: for pkg in pkgs {
			fullpath := str(pkg.fullpath)
			if len(array(pkg.entries)) == 0 {
				log.infof("Package at %s does not contain anything", fullpath)
				continue fullpath_loop
			}

			collection: ^Collection
			for c in cfg.collections {
				if strings.has_prefix(fullpath, c.root_path) {
					collection = c
					break
				}
			}

			if collection == nil {
				log.warnf(
					"Package at %s does not match any configured collections, skipping it",
					fullpath,
				)
				continue
			}

			log.debugf("Package %s belongs to collection %s", fullpath, collection.name)

			trimmed := strings.trim_prefix(fullpath, collection.root_path)
			trimmed = strings.trim_prefix(trimmed, collection.base_url[1:])
			trimmed = strings.trim_prefix(trimmed, "/")

			if strings.contains(trimmed, "/_") {
				log.infof(
					"Package %s is a system/os specific package and will be skipped",
					fullpath,
				)
				continue fullpath_loop
			}

			log.debugf("Final package path for %s: %q", str(pkg.name), trimmed)

			if trimmed not_in collection.pkgs {
				collection.pkgs[trimmed] = pkg
			}
			collection.pkg_to_path[pkg] = trimmed
			cfg.pkg_to_collection[pkg] = collection
			cfg.pkg_to_header[pkg] = cfg.header
		}
	}


	for c in cfg.collections {
		if c.root == nil {
			assert(all_packages)
			c.root = new(Dir_Node)
			c.root.children = make([dynamic]^Dir_Node)
		}
		insert_into_directory_tree(c.root, c.pkgs)
	}
}



print_usage :: proc() -> ! {
	fmt.eprintf(
		"%s is a program that generates a documentation website from a .odin-doc file and an optional config.",
		os.args[0],
	)
	fmt.eprintln()
	fmt.eprintln("usage:")
	fmt.eprintf("\t%s odin-doc-file [config-file]", os.args[0])
	fmt.eprintln()

	os.exit(1)
}

copy_assets :: proc() {
	if !os.write_entire_file("search.js", #load("resources/search.js")) {
		errorf("unable to write the search.js file")
	}

	if !os.write_entire_file("style.css", #load("resources/style.css")) {
		errorf("unable to write the style.css file")
	}

	if !os.write_entire_file("favicon.svg", #load("resources/favicon.svg")) {
		errorf("unable to write favicon.svg file")
	}
}

Header_Kind :: enum {
	Normal,
	Full_Width,
}

write_html_header :: proc(w: io.Writer, title: string, kind := Header_Kind.Normal) {
	fmt.wprintf(w, string(#load("resources/header.txt.html")), title)

	when #config(ODIN_DOC_DEV, false) {
		io.write_string(w, "\n")
		io.write_string(w, `<script type="text/javascript" src="https://livejs.com/live.js"></script>`)
		io.write_string(w, "\n")
	}


	io.write(w, #load("resources/header-lower.txt.html"))
	switch kind {
	case .Normal:
		io.write_string(w, `<div class="container">`+"\n")
	case .Full_Width:
		io.write_string(w, `<div class="container full-width">`+"\n")
	}
}

generate_json_pkg_data :: proc(b: ^strings.Builder, collections: []^Collection) {
	w := strings.to_writer(b)

	strings.builder_reset(b)
	now := time.now()
	fmt.wprintf(w, "/** Generated with odin version %s (vendor %q) %s_%s @ %v */\n", ODIN_VERSION, ODIN_VENDOR, ODIN_OS, ODIN_ARCH, now)
	fmt.wprint(w, "var odin_pkg_data = {\n")
	fmt.wprintln(w, `"packages": {`)


	base_collection: ^Collection
	for c in collections {
		if c.name == "base" {
			base_collection = c
			break
		}
	}

	pkg_idx := 0
	if base_collection != nil {
		if pkg_idx != 0 { fmt.wprintln(w, ",") }
		fmt.wprintf(w, "\t\"%s\": {{\n", "builtin")
		fmt.wprintf(w, "\t\t\"name\": \"%s\",\n", "builtin")
		fmt.wprintf(w, "\t\t\"collection\": \"%s\",\n", base_collection.name)
		fmt.wprintf(w, "\t\t\"path\": \"%s/%s\",\n", base_collection.base_url, "builtin")
		fmt.wprint(w, "\t\t\"entities\": [\n")

		for b, i in builtins {
			if i != 0 { fmt.wprint(w, ",\n") }
			fmt.wprint(w, "\t\t\t{")
			fmt.wprintf(w, `"kind": %q, `, b.kind)
			fmt.wprintf(w, `"name": %q, `, b.name)
			fmt.wprintf(w, `"type": %q, `, b.type)
			fmt.wprintf(w, `"builtin": %v, `, true)
			if len(b.comment) != 0 {
				fmt.wprintf(w, `"comment": %q`, b.comment)
			}
			fmt.wprint(w, "}")
		}

		fmt.wprint(w, "\n\t\t]")
		fmt.wprint(w, "\n\t}")
		pkg_idx += 1
	}

	if base_collection != nil {
		if pkg_idx != 0 { fmt.wprintln(w, ",") }
		fmt.wprintf(w, "\t\"%s\": {{\n", "intrinsics")
		fmt.wprintf(w, "\t\t\"name\": \"%s\",\n", "intrinsics")
		fmt.wprintf(w, "\t\t\"collection\": \"%s\",\n", base_collection.name)
		fmt.wprintf(w, "\t\t\"path\": \"%s/%s\",\n", base_collection.base_url, "intrinsics")
		fmt.wprint(w, "\t\t\"entities\": [\n")

		for b, i in intrinsics_table {
			if i != 0 { fmt.wprint(w, ",\n") }
			fmt.wprint(w, "\t\t\t{")
			fmt.wprintf(w, `"kind": %q, `, b.kind)
			fmt.wprintf(w, `"name": %q, `, b.name)
			fmt.wprintf(w, `"type": %q, `, b.type)
			fmt.wprintf(w, `"intrinsics": %v, `, true)
			if len(b.comment) != 0 {
				fmt.wprintf(w, `"comment": %q`, b.comment)
			}
			fmt.wprint(w, "}")
		}

		fmt.wprint(w, "\n\t\t]")
		fmt.wprint(w, "\n\t}")
		pkg_idx += 1
	}


	for collection in collections {
		for path, pkg in collection.pkgs {
			init_cfg_from_pkg(pkg)
			entries := collection.pkg_entries_map[pkg]
			if pkg_idx != 0 { fmt.wprintln(w, ",") }
			fmt.wprintf(w, "\t\"%s\": {{\n", str(pkg.name))
			fmt.wprintf(w, "\t\t\"name\": \"%s\",\n", str(pkg.name))
			fmt.wprintf(w, "\t\t\"collection\": \"%s\",\n", collection.name)
			fmt.wprintf(w, "\t\t\"path\": \"%s/%s\",\n", collection.base_url, path)
			fmt.wprint(w, "\t\t\"entities\": [\n")
			for e, i in entries.all {
				if i != 0 { fmt.wprint(w, ",\n") }

				kind_str := ""
				switch cfg.entities[e.entity].kind {
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
				fmt.wprintf(w, `"name": %q`, str(e.name))


				if str(pkg.name) == "runtime" {
					for attr in array(cfg.entities[e.entity].attributes) {
						if str(attr.name) == "builtin" {
							fmt.wprintf(w, `, "builtin": true`)
							break
						}
					}
				}

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

write_html_footer :: proc(w: io.Writer, include_directory_js: bool) {
	io.write_string(w, "\n")

	io.write(w, #load("resources/footer.txt.html"))
	fmt.wprintf(w, "</body>\n</html>\n")
}

init_pkg_entries_map :: proc(collection: ^Collection, node: ^Dir_Node) {
	if node.pkg != nil {
		init_cfg_from_pkg(node.pkg)
		collection.pkg_entries_map[node.pkg] = pkg_entries_gather(node.pkg)
	}
	for child in node.children {
		init_pkg_entries_map(collection, child)
	}
}


generate_package_from_directory_tree :: proc(b: ^strings.Builder, node: ^Dir_Node) -> (runtime_pkg: ^doc.Pkg) {
	if node.pkg != nil {
		pkg  := node.pkg
		collection := cfg.pkg_to_collection[pkg]
		path := collection.pkg_to_path[pkg]
		dir  := collection.name
		init_cfg_from_pkg(pkg)

		if str(pkg.name) == "runtime" {
			runtime_pkg = pkg
		}

		if str(pkg.fullpath) not_in cfg.pkgs_line_docs {
			line_doc, _, _ := strings.partition(str(pkg.docs), "\n")
			line_doc = strings.trim_space(line_doc)
			cfg.pkgs_line_docs[strings.clone(str(pkg.fullpath))] = strings.clone(line_doc)
		}

		strings.builder_reset(b)
		w := strings.to_writer(b)

		write_html_header(w, fmt.tprintf("package %s - pkg.odin-lang.org", path), .Full_Width)
		write_pkg(w, dir, path, pkg, collection, collection.pkg_entries_map[pkg])
		write_html_footer(w, false)
		recursive_make_directory(path, dir)
		os.write_entire_file(fmt.tprintf("%s/%s/index.html", dir, path), b.buf[:])
	}
	for child in node.children {
		res := generate_package_from_directory_tree(b, child)
		if runtime_pkg == nil {
			runtime_pkg = res
		}
	}

	return runtime_pkg
}

generate_packages_in_collection :: proc(b: ^strings.Builder, collection: ^Collection) {
	w := strings.to_writer(b)

	dir := collection.name

	init_pkg_entries_map(collection, collection.root)

	runtime_pkg := generate_package_from_directory_tree(b, collection.root)

	if runtime_pkg != nil &&
	   collection.name == "base" {
		init_cfg_from_pkg(runtime_pkg)

		path := "builtin"

		strings.builder_reset(b)
		write_html_header(w, fmt.tprintf("package %s - pkg.odin-lang.org", path), .Full_Width)
		write_builtin_pkg(w, dir, path, runtime_pkg, collection, "builtin", builtin_docs)
		write_html_footer(w, false)
		recursive_make_directory(path, dir)
		os.write_entire_file(fmt.tprintf("%s/%s/index.html", dir, path), b.buf[:])


		path = "intrinsics"
		strings.builder_reset(b)
		write_html_header(w, fmt.tprintf("package %s - pkg.odin-lang.org", path), .Full_Width)
		write_builtin_pkg(w, dir, path, runtime_pkg, collection, "intrinsics", intrinsics_docs)
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
	defer fmt.wprintln(w, `</ul>`)

	for c in cfg.collections {
		if c.hidden do continue

		fmt.wprintf(
			w,
			`<li class="nav-item"><a class="nav-link" style="text-transform: capitalize;" href="%s">%s Library</a></li>`,
			c.base_url,
			c.name,
		)
	}
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

	for c in cfg.collections {
		if cfg.hide_base && (c.name == "base") {
			continue
		}
		if cfg.hide_core && (c.name == "core" || c.name == "vendor") {
			continue
		}

		fmt.wprintln(w, `<div class="mt-5">`)
			defer fmt.wprintln(w, `</div>`)

			fmt.wprintf(
				w,
				`<a href="%s" class="link-primary text-decoration-node"><h3>%s</h3></a>`,
				c.base_url,
				c.home.title.? or_else c.name,
			)

			if d, ok := c.home.description.?; ok {
				fmt.wprintf(w, `<p>%s</p>`, d)
			}

		if path, ok := c.home.embed_readme.?; ok {
			log.infof("Writing readme from path at: %s", path)
			write_readme(w, path)
		}
	}
}

write_readme :: proc(w: io.Writer, path: string) {
	data, ok := os.read_entire_file_from_filename(path)
	if !ok {
		log.errorf("Could not read the file %q to render the readme", path)
		return
	}
	defer delete(data)

	root := cm.parse_document_from_string(string(data), cm.DEFAULT_OPTIONS)
	defer cm.node_free(root)

	log.debug("Removing first h1 from the readme (checking first 5 nodes)")

	iter := cm.iter_new(root)
	defer cm.iter_free(iter)
	for _ in 0 ..= 5 {
		node := cm.iter_get_node(iter)
		log.debugf("Checking node %s", cm.node_get_type_string(node))

		if cm.node_get_heading_level(node) == 1 {
			cm.node_unlink(node)
			cm.node_free(node)
			log.debug("Removing node")
			break
		}

		cm.iter_next(iter)
	}

	html := cm.render_html(root, cm.DEFAULT_OPTIONS)
	defer cm.free(html)

	io.write_string(w, string(html))
}

target_from_pkg :: proc(pkg: ^doc.Pkg) -> (target: string, ok: bool) {
	if pkg == nil {
		return
	}
	path := cfg.pkg_to_collection[pkg].pkg_to_path[pkg]
	dir, _, name := strings.partition(path, "/")
	if strings.contains(dir, "sys") {
		target = "windows_amd64"
		ok = true
		switch name {
		case "darwin":
			target = "darwin_arm64"
		case "linux", "unix":
			target = "linux_arm64"
		case "haiku":
			target = "haiku_arm64"
		}
	}
	return
}


write_collection_directory :: proc(w: io.Writer, collection: ^Collection) {
	get_line_doc :: proc(pkg: ^doc.Pkg) -> (line_doc: string, ok: bool) {
		if pkg == nil {
			return
		}
		line_doc = cfg.pkgs_line_docs[str(pkg.fullpath)]
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


	fmt.wprintln(w, `<div class="row odin-main my-4">`)
	defer fmt.wprintln(w, `</div>`)

	write_pkg_sidebar(w, nil, collection, "")

	fmt.wprintln(w, `<article class="col-lg-10 p-4">`)
	defer fmt.wprintln(w, `</article>`)
	{
		fmt.wprintln(w, `<article class="p-4">`)
		fmt.wprintln(w, `<header class="collection-header">`)
		fmt.wprintf(
			w,
			"<h1 style=\"text-transform: capitalize\">%s Library Collection</h1>\n",
			collection.name,
		)

		write_license(w, collection)
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

	write_directory :: proc(w: io.Writer, dir: ^Dir_Node, collection: ^Collection) {
		if len(dir.children) != 0 {
			fmt.wprint(w, `<tr aria-controls="`)
			for child in dir.children {
				fmt.wprintf(w, "pkg-%s ", child.name)
			}
			fmt.wprint(w, `" class="directory-pkg"><td class="pkg-line pkg-name" data-aria-owns="`)
			for child in dir.children {
				fmt.wprintf(w, "pkg-%s ", child.name)
			}
			fmt.wprintf(w, `" id="pkg-%s">`, dir.dir)
		} else {
			fmt.wprintf(w, `<tr id="pkg-%s" class="directory-pkg"><td class="pkg-name">`, dir.dir)
		}

		if dir.pkg != nil {
			init_cfg_from_pkg(dir.pkg)
			fmt.wprintf(w, `<a href="%s/%s">%s</a>`, collection.base_url, dir.path, dir.name)
		} else if dir.name == "builtin" || dir.name == "intrinsics" {
			fmt.wprintf(w, `<a href="%s/%s">%s</a>`, collection.base_url, dir.path, dir.name)
		} else {
			fmt.wprintf(w, "%s", dir.name)
		}
		io.write_string(w, `</td>`)
		io.write_string(w, `<td class="pkg-line pkg-line-doc">`)
		if line_doc, ok := get_line_doc(dir.pkg); ok {
			write_doc_line(w, line_doc)
		} else if dir.name == "builtin" {
			first, _, _ := strings.partition(builtin_docs, ".")
			write_doc_line(w, first)
			io.write_string(w, `.`)
		} else if dir.name == "intrinsics" {
			first, _, _ := strings.partition(intrinsics_docs, ".")
			write_doc_line(w, first)
			io.write_string(w, `.`)
		} else {
			if dir.dir == "sys" {
				io.write_string(w, `Platform specific packages - documentation may be for a specific platform only`)
			} else {
				io.write_string(w, `&nbsp;`)
			}
		}
		io.write_string(w, `</td>`)
		fmt.wprintf(w, "</tr>\n")

		for child in dir.children {
			assert(child.pkg != nil)
			init_cfg_from_pkg(child.pkg)

			fmt.wprintf(w, `<tr id="pkg-%s" class="directory-pkg directory-child"><td class="pkg-line pkg-name">`, child.name)
			fmt.wprintf(w, `<a href="%s/%s/">%s</a>`, collection.base_url, child.path, child.name)
			io.write_string(w, `</td>`)

			io.write_string(w, `<td class="pkg-line pkg-line-doc">`)
			if child_line_doc, ok := get_line_doc(child.pkg); ok {
				write_doc_line(w, child_line_doc)
			} else if target, target_ok := target_from_pkg(child.pkg); target_ok {
				fmt.wprintf(w, `<em>(Generated with <code>-target:%s</code>, please read the source code directly)</em>`, target)
			} else {
				io.write_string(w, `&nbsp;`)
			}
			io.write_string(w, `</td>`)

			fmt.wprintf(w, "</td>")
			fmt.wprintf(w, "</tr>\n")
		}
	}

	if collection.name == "base" {
		write_directory(w, &Dir_Node{
			dir = "builtin",
			path = "builtin",
			name = "builtin",
			pkg = nil,
			children = nil,
		}, collection)
		write_directory(w, &Dir_Node{
			dir = "intrinsics",
			path = "intrinsics",
			name = "intrinsics",
			pkg = nil,
			children = nil,
		}, collection)
	}

	for dir in collection.root.children {
		write_directory(w, dir, collection)
	}

	fmt.wprintln(w, "\t\t</tbody>")
	fmt.wprintln(w, "\t</table>")
	fmt.wprintln(w, "</div>")
}

write_license :: proc(w: io.Writer, collection: ^Collection) {
	fmt.wprintln(w, "<ul class=\"license\">")
	fmt.wprintf(
		w,
		"<li>License: <a href=\"%s\">%s</a></li>\n",
		collection.license.url,
		collection.license.text,
	)
	fmt.wprintf(w, "<li>Repository: <a href=\"{0:s}\">{0:s}</a></li>\n", collection.source_url)
	fmt.wprintln(w, "</ul>")
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
		e := &cfg.entities[entity_index]
		name := str(e.name)
		name_width = max(len(name), name_width)
	}
	return
}

entity_flag_strings := #sparse[doc.Entity_Flag]string{
	.Foreign                = "",
	.Export                 = "",

	.Param_Using            = "using",
	.Param_Const            = "#const",
	.Param_Auto_Cast        = "#auto_cast",
	.Param_Ellipsis         = "..",
	.Param_CVararg          = "#c_vararg",
	.Param_No_Alias         = "#no_alias",
	.Param_Any_Int          = "#any_int",
	.Param_By_Ptr           = "#by_ptr",
	.Param_No_Broadcast     = "#no_broadcast",

	.Bit_Field_Field        = "",

	.Type_Alias             = "",

	.Builtin_Pkg_Builtin    = "",
	.Builtin_Pkg_Intrinsics = "",

	.Var_Thread_Local       = "",
	.Var_Static             = "",

	.Private                = "",
}

write_type :: proc(using writer: ^Type_Writer, type: doc.Type, flags: Write_Type_Flags) {
	write_param_entity :: proc(using writer: ^Type_Writer, e, next_entity: ^doc.Entity, flags: Write_Type_Flags, name_width := 0) {
		name := str(e.name)
		name_width := name_width

		write_padding :: proc(w: io.Writer, name: string, name_width: int) {
			for _ in 0..<name_width-len(name) {
				io.write_byte(w, ' ')
			}
		}

		for flag in e.flags {
			if str := entity_flag_strings[flag]; str != "" {
				io.write_string(w, `<span class="keyword-type">`)
				io.write_string(w, str)
				io.write_string(w, `</span> `)
				name_width -= 1+len(str)
			}
		}

		base := cfg._collections["base"]

		init_string := escape_html_string(str(e.init_string))
		switch {
		case init_string == "#caller_location":
			assert(name != "")
			io.write_string(w, name)
			io.write_string(w, " := ")
			fmt.wprintf(w, `<a href="%s/runtime/#Source_Code_Location">`, base.base_url)
			io.write_string(w, init_string)
			io.write_string(w, `</a>`)
		case strings.has_prefix(init_string, "context."):
			io.write_string(w, name)
			io.write_string(w, " := ")
			fmt.wprintf(w, `<a href="%s/runtime/#Context">`, base.base_url)
			io.write_string(w, init_string)
			io.write_string(w, `</a>`)
		case:
			the_type := cfg.types[e.type]
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
					io.write_string(w, `<span class="keyword-type">typeid</span>`)
					if ts := array(the_type.types); len(ts) == 1 {
						io.write_byte(w, '/')
						write_type(writer, cfg.types[ts[0]], type_flags)
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
			write_type(writer, cfg.types[type.polymorphic_params], flags+{.Poly_Names})
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
			e := &cfg.entities[entity_index]
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
		docs := docs
		if docs == "" {
			return
		}
		docs = escape_html_string(docs)
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
		comment := comment
		if comment == "" {
			return
		}
		comment = escape_html_string(comment)
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
		_ = type_flags
		if is_type_untyped(type) {
			io.write_string(w, str(type.name))
		} else {
			fmt.wprintf(w, `<a href="/base/builtin#{0:s}"><span class="doc-builtin">{0:s}</span></a>`, str(type.name))
			// io.write_string(w, str(type.name))
		}
	case .Named:
		e := cfg.entities[type_entities[0]]
		name := str(type.name)
		tn_pkg := cfg.files[e.pos.file].pkg
		collection: Collection
		if c := cfg.pkg_to_collection[&cfg.pkgs[tn_pkg]]; c != nil {
			collection = c^
		}

		if tn_pkg != pkg {
			// remove the extra prefix e.g. `foo.foo.bar`
			name_prefix := name
			if n := strings.index_byte(name_prefix, '('); n >= 0 {
				name_prefix = name_prefix[:n]
			}
			if !strings.contains_rune(name_prefix, '.') {
				fmt.wprintf(w, `%s.`, str(cfg.pkgs[tn_pkg].name))
			}
		}
		if .Private in e.flags {
			io.write_string(w, name)
		} else if n := strings.index_rune(name, '('); n >= 0 {
			fmt.wprintf(
				w,
				`<a class="code-typename" href="{2:s}/{0:s}/#{1:s}">{1:s}</a>`,
				collection.pkg_to_path[&cfg.pkgs[tn_pkg]],
				name[:n],
				collection.base_url,
			)
			io.write_string(w, name[n:])
		} else {
			fmt.wprintf(
				w,
				`<a class="code-typename" href="{2:s}/{0:s}/#{1:s}">{1:s}</a>`,
				collection.pkg_to_path[&cfg.pkgs[tn_pkg]],
				name,
				collection.base_url,
			)
		}
	case .Generic:
		name := str(type.name)
		if name not_in generic_scope {
			io.write_byte(w, '$')
		}
		io.write_string(w, name)
		if name not_in generic_scope && len(array(type.types)) == 1 {
			io.write_byte(w, '/')
			write_type(writer, cfg.types[type_types[0]], flags)
		}
	case .Pointer:
		io.write_byte(w, '^')
		write_type(writer, cfg.types[type_types[0]], flags)
	case .Array:
		assert(type.elem_count_len == 1)
		io.write_byte(w, '[')
		io.write_uint(w, uint(type.elem_counts[0]))
		io.write_byte(w, ']')
		write_type(writer, cfg.types[type_types[0]], flags)
	case .Enumerated_Array:
		io.write_byte(w, '[')
		write_type(writer, cfg.types[type_types[0]], flags)
		io.write_byte(w, ']')
		write_type(writer, cfg.types[type_types[1]], flags)
	case .Slice:
		if .Variadic in flags {
			io.write_string(w, "..")
		} else {
			io.write_string(w, "[]")
		}
		write_type(writer, cfg.types[type_types[0]], flags - {.Variadic})
	case .Dynamic_Array:
		io.write_string(w, "[<span class=\"keyword\">dynamic</span>]")
		write_type(writer, cfg.types[type_types[0]], flags)
	case .Map:
		io.write_string(w, "<span class=\"keyword-type\">map</span>[")
		write_type(writer, cfg.types[type_types[0]], flags)
		io.write_byte(w, ']')
		write_type(writer, cfg.types[type_types[1]], flags)
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
				e := &cfg.entities[entity_index]
				docs, comment := str(e.docs), str(e.comment)
				_ = comment

				write_lead_comment(writer, flags, docs, i)

				do_indent(writer, flags)
				write_param_entity(writer, e, /*next_entity*/nil, flags, name_width)

				if tag := str(tags[i]); tag != "" {
					io.write_string(w, " <span class=\"string\">`")
					io.write_string(w, tag)
					io.write_string(w, "`</span>")
					// io.write_byte(w, ' ')
					// io.write_quoted_string(w, tag)
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
				write_type(writer, cfg.types[type_index], flags)
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
			write_type(writer, cfg.types[type_types[0]], flags)
		}
		io.write_string(w, " {")
		do_newline(writer, flags)
		indent += 1

		name_width := calc_name_width(type_entities)
		field_width := calc_field_width(type_entities)

		for entity_index, i in type_entities {
			e := &cfg.entities[entity_index]
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
		for entity_index in type_entities {
			e := &cfg.entities[entity_index]
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
		flags := flags
		if all_blank {
			flags += {.Ignore_Name}
		}

		span_multiple_lines := false
		if .Allow_Multiple_Lines in flags && .Is_Results not_in flags {
			span_multiple_lines = len(type_entities) >= 6

			if strings.has_prefix(str(cfg.pkgs[pkg].name), "objc_") {
				span_multiple_lines = true
			}
		}

		full_name_width :: proc(entity_indices: []doc.Entity_Index) -> (width: int) {
			for entity_index, i in entity_indices {
				if i > 0 {
					width += 2
				}
				width += len(str(cfg.entities[entity_index].name))
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
					e = &cfg.entities[type_entities[i]]
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
			for group in groups {
				io.write_string(w, "\n\t")
				group_name_width := full_name_width(group)
				for entity_index, i in group {
					defer j += 1


					e := &cfg.entities[entity_index]
					next_entity: ^doc.Entity = nil
					if j+1 < len(type_entities) {
						next_entity = &cfg.entities[type_entities[j+1]]
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
				e := &cfg.entities[entity_index]

				if i > 0 {
					io.write_string(w, ", ")
				}
				next_entity: ^doc.Entity = nil
				if i+1 < len(type_entities) {
					next_entity = &cfg.entities[type_entities[i+1]]
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
			io.write_string(w, " <span class=\"string\">")
			io.write_quoted_string(w, cc)
			io.write_string(w, "</span> ")
		}
		params := array(type.types)[0]
		results := array(type.types)[1]
		io.write_byte(w, '(')
		write_type(writer, cfg.types[params], flags)
		io.write_byte(w, ')')
		if results != 0 {
			assert(.Diverging not_in type_flags)
			io.write_string(w, " -> ")
			write_type(writer, cfg.types[results], flags+{.Is_Results})
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
			write_type(writer, cfg.types[type_types[0]], flags)
		}
		if .Underlying_Type in type_flags {
			io.write_string(w, "; ")
			write_type(writer, cfg.types[type_types[1]], flags)
		}
		io.write_string(w, "]")
	case .Simd_Vector:
		io.write_string(w, "<span class=\"directive\">#simd</span>[")
		io.write_uint(w, uint(type.elem_counts[0]))
		io.write_byte(w, ']')
		write_type(writer, cfg.types[type_types[0]], flags)
	case .SOA_Struct_Fixed:
		io.write_string(w, "<span class=\"directive\">#soa</span>[")
		io.write_uint(w, uint(type.elem_counts[0]))
		io.write_byte(w, ']')
		write_type(writer, cfg.types[type_types[0]], flags)
	case .SOA_Struct_Slice:
		io.write_string(w, "<span class=\"directive\">#soa</span>[]")
		write_type(writer, cfg.types[type_types[0]], flags)
	case .SOA_Struct_Dynamic:
		io.write_string(w, "<span class=\"directive\">#soa</span>[<span class=\"keyword\">dynamic</span>]")
		write_type(writer, cfg.types[type_types[0]], flags)
	case .Soa_Pointer:
		io.write_string(w, "<span class=\"directive\">#soa</span>^")
		if len(type_types) != 0 && len(cfg.types) != 0 {
			write_type(writer, cfg.types[type_types[0]], flags)
		}
	case .Relative_Pointer:
		io.write_string(w, "<span class=\"directive\">#relative</span>(")
		write_type(writer, cfg.types[type_types[1]], flags)
		io.write_string(w, ") ")
		write_type(writer, cfg.types[type_types[0]], flags)
	case .Relative_Multi_Pointer:
		io.write_string(w, "<span class=\"directive\">#relative</span>(")
		write_type(writer, cfg.types[type_types[1]], flags)
		io.write_string(w, ") ")
		write_type(writer, cfg.types[type_types[0]], flags)
	case .Multi_Pointer:
		io.write_string(w, "[^]")
		write_type(writer, cfg.types[type_types[0]], flags)
	case .Matrix:
		io.write_string(w, "<span class=\"keyword-type\">matrix</span>[")
		io.write_uint(w, uint(type.elem_counts[0]))
		io.write_string(w, ", ")
		io.write_uint(w, uint(type.elem_counts[1]))
		io.write_string(w, "]")
		write_type(writer, cfg.types[type_types[0]], flags)

	case .Bit_Field:
		io.write_string(w, "<span class=\"keyword-type\">bit_field</span>&nbsp;")
		write_type(writer, cfg.types[type_types[0]], flags)
		io.write_string(w, " {")

		if len(type_entities) != 0 {
			do_newline(writer, flags)
			indent += 1
			name_width := calc_name_width(type_entities)

			for entity_index, i in type_entities {
				e := &cfg.entities[entity_index]
				next_entity: ^doc.Entity = nil
				if i+1 < len(type_entities) {
					next_entity = &cfg.entities[type_entities[i+1]]
				}
				docs, comment := str(e.docs), str(e.comment)
				_ = comment

				write_lead_comment(writer, flags, docs, i)

				do_indent(writer, flags)
				write_param_entity(writer, e, next_entity, flags, name_width)

				io.write_string(w, " | ")
				io.write_int(w, max(int(-e.field_group_index), 0))
				io.write_byte(w, ',')
				do_newline(writer, flags)
			}
			indent -= 1
			do_indent(writer, flags)
		}
		io.write_string(w, "}")
	}
}

write_doc_line :: proc(w: io.Writer, text: string) {
	text := text
	text = escape_html_string(text)
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

write_markup_text :: proc(w: io.Writer, s_: string) {
	// We need to ensure that we don't escape html tags in our docs
	s := escape_html_string(s_)
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
		case '[':
			if index+1 < len(s) && s[index+1] == '[' {
				end_bracket := strings.index(s[index + 1:], "]]")
				slash_slash := strings.index(s[index + 1:], "//")
				if end_bracket >= 0 && slash_slash < end_bracket {
					end_bracket += index + 2

					text := s[index + 2:end_bracket-1]
					url := text
					if strings.contains(text, ";") {
						text, _, url = strings.partition(text, ";")
					}
					text = strings.trim_space(text)
					url  = strings.trim_space(url)

					io.write_string(w, s[latest_index:index])
					fmt.wprintf(w, `<a href="%s">`, url)
					io.write_string(w, text)
					io.write_string(w, "</a>")
					latest_index = end_bracket + 1
					index = latest_index

				}
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

	trim_empty_and_subtitle_lines_and_replace_lt :: proc(lines: []string, subtitle: string) -> []string {
		lines := lines
		for len(lines) > 0 && (strings.trim_space(lines[0]) == "" || strings.has_prefix(lines[0], subtitle)) {
			lines = lines[1:]
		}
		for len(lines) > 0 && (strings.trim_space(lines[len(lines) - 1]) == "") {
			lines = lines[:len(lines) - 1]
		}
		for &line in lines {
			line = escape_html_string(line)
		}
		return lines
	}

	if docs == "" {
		return
	}

	Block_Kind :: enum {
		Paragraph,
		Code,
		Example,
		Output,
		Possible_Output,
	}
	Block :: struct {
		kind: Block_Kind,
		lines: []string,
	}

	lines_to_process := strings.split_lines(docs)
	curr_block_kind := Block_Kind.Paragraph
	start := 0
	blocks: [dynamic]Block

	has_any_output: bool
	has_example: bool

	// Find the minimum common prefix length of tabs, so an entire doc comment can be indented
	// without it rendering in a <pre> tag.
	first_line_special := strings.has_prefix(lines_to_process[0], "Example:") || strings.has_prefix(lines_to_process[0], "Output:") || strings.has_prefix(lines_to_process[0], "Possible Output:")
	if !first_line_special && len(lines_to_process) > 1 {
		min_tabs: Maybe(int)
		for line in lines_to_process[1:] {
			if len(strings.trim_space(line)) == 0 {
				continue
			}

			tabs: int
			for ch in line {
				if ch == '\t' {
					tabs += 1
				} else {
					break
				}
			}
			min_tabs = min(tabs, min_tabs.? or_else max(int))
		}
		if min, has_min := min_tabs.?; has_min {
			for &line in lines_to_process[1:] {
				if len(strings.trim_space(line)) == 0 {
					continue
				}
				line = line[min:]
			}
		}
	}

	for line, i in lines_to_process {
		text := strings.trim_space(line)
		next_block_kind := curr_block_kind
		force_write_block := false

		switch curr_block_kind {
		case .Paragraph:
			switch {
			case strings.has_prefix(line, "Example:"):
				next_block_kind = .Example
				has_example = true
			case strings.has_prefix(line, "Output:"):
				next_block_kind = .Output
				has_any_output = true
			case strings.has_prefix(line, "Possible Output:"):
				next_block_kind = .Possible_Output
				has_any_output = true
			case strings.has_prefix(line, "\t"): next_block_kind = .Code
			case text == "": force_write_block = true
			}
		case .Code:
			switch {
			case strings.has_prefix(line, "Example:"):
				next_block_kind = .Example
				has_example = true
			case strings.has_prefix(line, "Output:"):
				next_block_kind = .Output
				has_any_output = true
			case strings.has_prefix(line, "Possible Output:"):
				next_block_kind = .Possible_Output
				has_any_output = true
			case !strings.has_prefix(line, "\t") && text != "":
				next_block_kind = .Paragraph
			}
		case .Example:
			switch {
			case strings.has_prefix(line, "Output:"):
				next_block_kind = .Output
				has_any_output = true
			case strings.has_prefix(line, "Possible Output:"):
				next_block_kind = .Possible_Output
				has_any_output = true
			case !strings.has_prefix(line, "\t") && text != "":
				next_block_kind = .Paragraph
			}
		case .Output, .Possible_Output:
			switch {
			case strings.has_prefix(line, "Example:"):
				next_block_kind = .Example
				has_example = true
			case !strings.has_prefix(line, "\t") && text != "":
				next_block_kind = .Paragraph
			}
		}

		if curr_block_kind != next_block_kind || force_write_block {
			append(&blocks, Block{curr_block_kind, lines_to_process[start:i]})
			curr_block_kind = next_block_kind
			start = i
		}
	}

	if start < len(lines_to_process) {
		append(&blocks, Block{curr_block_kind, lines_to_process[start:]})
	}

	if has_any_output && !has_example {
		errorf("The documentation for %q has an output block but no example\n", name)
	}

	for &block in blocks {
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

		block_lines := block.lines[:]

		switch block.kind {
		case .Paragraph:
			io.write_string(w, "<p>")

			subtitles_to_markup := [?]string{ "Inputs:", "Returns:" }
			for subtitle in subtitles_to_markup {
				if ! strings.has_prefix(block_lines[0], subtitle) {
					continue
				}
				fmt.wprintf(w, "<b>%v</b><br>", subtitle)
				removed_subtitle := strings.trim_prefix(block_lines[0], subtitle)
				removed_subtitle = strings.trim_left_space(removed_subtitle)
				if removed_subtitle == "" {
					block_lines = block_lines[1:]
				} else {
					block_lines[0] = removed_subtitle
				}
				break
			}

			for line, line_idx in block_lines {
				if line_idx > 0 {
					io.write_string(w, "\n")
				}
				write_markup_text(w, line)
			}
			io.write_string(w, "</p>\n")
		case .Code:
			all_blank := len(block_lines) > 0
			for line in block_lines {
				if strings.trim_space(line) != "" {
					all_blank = false
				}
			}
			if all_blank {
				continue
			}

			io.write_string(w, "<pre>")
			for line in block.lines {
				trimmed := strings.trim_prefix(line, "\t")
				s := escape_html_string(trimmed)
				io.write_string(w, s)
				io.write_string(w, "\n")
			}
			io.write_string(w, "</pre>\n")
		case .Example:
			// Example block starts with `Example:` and a number of white spaces,
			example_lines := trim_empty_and_subtitle_lines_and_replace_lt(block.lines, "Example:")

			io.write_string(w, "<details open class=\"code-example\">\n")
			defer io.write_string(w, "</details>\n")
			io.write_string(w, "<summary><b>Example:</b></summary>\n")
			io.write_string(w, `<pre><code class="hljs language-odin" data-lang="odin">`)
			for line in example_lines {
				io.write_string(w, strings.trim_prefix(line, "\t"))
				io.write_string(w, "\n")
			}
			io.write_string(w, "</code></pre>\n")

		case .Output, .Possible_Output:
			// Output block starts with `Output:` or `Possible Output:` and a number of white spaces,
			output_lines := trim_empty_and_subtitle_lines_and_replace_lt(block.lines, block.kind == .Possible_Output ? "Possible Output:" : "Output:")

			io.write_string(w, block.kind == .Possible_Output ? "<b>Possible Output:</b>" : "<b>Output:</b>\n")
			io.write_string(w, `<pre class="doc-code">`)
			for line in output_lines {
				io.write_string(w, strings.trim_prefix(line, "\t"))
				io.write_string(w, "\n")
			}
			io.write_string(w, "</pre>\n")
		}
	}
}

write_pkg_sidebar :: proc(w: io.Writer, curr_pkg: ^doc.Pkg, collection: ^Collection, pkg_name: string) {

	fmt.wprintln(w, `<nav id="pkg-sidebar" class="col-lg-2 odin-sidebar-border navbar-light sticky-top odin-below-navbar">`)
	defer fmt.wprintln(w, `</nav>`)
	fmt.wprintln(w, `<div class="py-3">`)
	defer fmt.wprintln(w, `</div>`)

	fmt.wprintf(
		w,
		"<h4><a style=\"text-transform: capitalize; color: inherit;\" href=\"%s\">%s Library</a></h4>\n",
		collection.base_url,
		collection.name,
	)

	fmt.wprintln(w, `<ul>`)
	defer fmt.wprintln(w, `</ul>`)

	write_side_bar_item :: proc(w: io.Writer, curr_pkg: ^doc.Pkg, collection: ^Collection, dir: ^Dir_Node, is_active: bool) {
		fmt.wprint(w, `<li class="nav-item">`)
		defer fmt.wprintln(w, `</li>`)
		if dir.pkg == curr_pkg && (curr_pkg != nil || is_active) {
			fmt.wprintf(w, `<a class="active" href="%s/%s">%s</a>`, collection.base_url, dir.path, dir.name)
		} else if dir.pkg != nil || dir.name == "builtin" || dir.name == "intrinsics" {
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

	if collection.name == "base" {
		write_side_bar_item(w, curr_pkg, collection, &Dir_Node{
				dir = "builtin",
				path = "builtin",
				name = "builtin",
				pkg = nil,
				children = nil,
			},
			is_active = pkg_name=="builtin",
		)
		write_side_bar_item(w, curr_pkg, collection, &Dir_Node{
				dir = "intrinsics",
				path = "intrinsics",
				name = "intrinsics",
				pkg = nil,
				children = nil,
			},
			is_active = pkg_name=="intrinsics",
		)
	}

	for dir in collection.root.children {
		write_side_bar_item(w, curr_pkg, collection, dir, false)
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

		// When the collection and the package are at the same root path.
		if trimmed_path == "" do continue

		if trimmed_path in collection.pkgs {
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

entity_key :: proc(entry: doc.Scope_Entry) -> string {
	return str(entry.name)
}

pkg_entries_gather :: proc(pkg: ^doc.Pkg) -> (entries: Pkg_Entries) {
	for entry in array(pkg.entries) {
		e := &cfg.entities[entry.entity]
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
	fmt.wprintf(w, `
		<div class="odin-search-wrapper">
			<input type="search" id="odin-search" class="%s" autocomplete="off" spellcheck="false" placeholder="Fuzzy Search...">
			<div class="odin-search-shortcut">
				<div class="odin-search-key key-macos">⌘K</div>
				<div class="odin-search-key key-windows">Ctrl+K</div>
				<span class="odin-search-or">or</span>
				<div class="odin-search-key">/</div>
			</div>
		</div>
	`, class)
	fmt.wprintln(w)

	fmt.wprintln(w, `<div id="odin-search-info">`)
	fmt.wprintln(w, `<div id="odin-search-time"></div>`)
	if kind == .Package {
		fmt.wprintln(w, `
		<div id="odin-search-options">
			<input type="checkbox" id="odin-search-filter" name="odin-search-filter">
			<label for="odin-search-filter">Filter Results</label>
		</div>`)
	}
	fmt.wprintln(w, `</div>`)
	fmt.wprintln(w, `<ul id="odin-search-results"></ul>`)
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
		entity := &cfg.entities[entry.entity]
		if entity.kind == .Type_Name && str(entity.name) == objc_type {
			parent = entity
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
		pt := base_type(cfg.types[e.type])
		pentities: []doc.Entity_Index
		rentities: []doc.Entity_Index

		params := &cfg.types[array(pt.types)[0]]
		if params.kind == .Tuple {
			pentities = array(params.entities)
			if !is_class_method {
				pentities = pentities[1:]
			}
		}

		results := &cfg.types[array(pt.types)[1]]
		if results.kind == .Tuple {
			rentities = array(results.entities)
		}

		if len(rentities) != 0 {
			for e_idx, i in rentities {
				if i != 0 {
					fmt.wprintf(w, ", ")
				}
				entity := &cfg.entities[e_idx]
				name := str(entity.name)
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
			for entity_idx in pentities {
				entity := &cfg.entities[entity_idx]
				fmt.wprintf(w, "\t%s,\n", str(entity.name))
			}
		} else {
			for e_idx, i in pentities {
				if i != 0 {
					fmt.wprintf(w, ", ")
				}
				entity := &cfg.entities[e_idx]
				fmt.wprintf(w, "%s", str(entity.name))
			}
		}
		fmt.wprintf(w, ")\n")
	}

	#partial switch e.kind {
	case .Procedure:
		write_syntax_usage(w, e, objc_name, parent, is_class_method)
	case .Proc_Group:
		for e_idx in array(e.grouped_entities) {
			entity := &cfg.entities[e_idx]
			write_syntax_usage(w, entity, objc_name, parent, is_class_method)
		}
	}

	fmt.wprintln(w, "</pre>")
	return true
}

write_objc_methods :: proc(w: io.Writer, pkg: ^doc.Pkg, parent: ^doc.Entity, method_names_seen: ^map[string]bool, is_inherited := false) {
	methods: [dynamic]^doc.Entity

	parent_name := str(parent.name)

	for entry in array(pkg.entries) {
		e := &cfg.entities[entry.entity]
		if e.kind == .Proc_Group {
			if type_name, ok := find_entity_attribute(e, "objc_type"); ok && parent_name == type_name {
				append(&methods, e)
			}
		}
	}
	for entry in array(pkg.entries) {
		e := &cfg.entities[entry.entity]
		if e.kind == .Procedure {
			if type_name, ok := find_entity_attribute(e, "objc_type"); ok && parent_name == type_name {
				append(&methods, e)
			}
		}
	}

	seen_item := false


	slice.sort_by_key(methods[:], proc(e: ^doc.Entity) -> string {
		return str(e.name)
	})

	loop: for e in methods {
		method_name := find_entity_attribute(e, "objc_name") or_else panic("unable to find objc_name")
		method_name, _ = strconv.unquote_string(method_name) or_else panic("unable to unquote method name")

		if method_names_seen[method_name] {
			continue loop
		}

		collection := cfg.pkg_to_collection[pkg]

		method_names_seen[method_name] = true
		if !seen_item {
			if is_inherited {
				fmt.wprintf(
					w,
					`<h6>Methods Inherited From <a href="%s/%s/#%s">%s</a></h6>`,
					collection.base_url,
					collection.pkg_to_path[pkg],
					parent_name,
					parent_name,
				)
				fmt.wprintln(w)
			} else {
				fmt.wprintln(w, "<h5>Bound Objective-C Methods</h5>")
			}
			fmt.wprintln(w, "<ul>")
			seen_item = true
		}

		fmt.wprintf(w, "<li>")
		fmt.wprintf(
			w,
			`<a href="%s/%s/#%s">%s</a>`,
			collection.base_url,
			collection.pkg_to_path[pkg],
			str(e.name),
			method_name,
		)

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
		parent_type := base_type(cfg.types[parent.type])
		(parent_type.kind == .Struct) or_break recursive_inheritance_check
		fields := array(parent_type.entities)
		for field_idx := len(fields)-1; field_idx >= 0; field_idx -= 1 {
			field := &cfg.entities[fields[field_idx]]
			if .Param_Using in field.flags {
				field_type := cfg.types[field.type]
				field_type_entity := &cfg.entities[array(field_type.entities)[0]]
				field_pkg := &cfg.pkgs[cfg.files[field.pos.file].pkg]
				write_objc_methods(w, field_pkg, field_type_entity, method_names_seen, true)
			}
		}
	}
}

write_related_constants :: proc(w: io.Writer, pkg: ^doc.Pkg, parent: ^doc.Entity) {
	#partial switch pt := cfg.types[parent.type]; pt.kind {
	case .Invalid, .Basic, .Generic:
		// ignore non-useful types
		return
	}

	related_constants: [dynamic]^doc.Entity
	defer delete(related_constants)

	for entry in array(pkg.entries) {
		e := &cfg.entities[entry.entity]
		if e.kind == .Constant && e.type == parent.type {
			if strings.has_prefix(str(e.name), "_") {
				continue
			}
			append(&related_constants, e)
		}
	}

	if len(related_constants) == 0 {
		return
	}

	the_sort_proc :: proc(a, b: ^doc.Entity) -> (cmp: slice.Ordering) {
		cmp = slice.cmp(a.kind, b.kind)
		if cmp != .Equal { return }
		cmp = slice.cmp(str(a.name), str(b.name))
		return
	}

	slice.sort_by_cmp(related_constants[:], the_sort_proc)

	constants_seen := make(map[string]bool)
	defer delete(constants_seen)

	fmt.wprintfln(w, "<h5>Related Constants</h5>")
	fmt.wprintln(w, "<ul>")
	parameter_loop: for e in related_constants {
		proc_name := str(e.name)

		if constants_seen[proc_name] {
			continue parameter_loop
		}
		constants_seen[proc_name] = true

		collection := cfg.pkg_to_collection[pkg]
		fmt.wprintf(w, "<li>")
		fmt.wprintf(
			w,
			`<a href="%s/%s/#%s">%s</a>`,
			collection.base_url,
			collection.pkg_to_path[pkg],
			proc_name,
			proc_name,
		)
		fmt.wprintfln(w, "</li>")
	}
	fmt.wprintln(w, "</ul>")

}

write_related_procedures :: proc(w: io.Writer, pkg: ^doc.Pkg, parent: ^doc.Entity, proc_names_seen: ^map[string]bool, is_inherited := false) {
	related_procs_in_parameters, related_procs_in_return_types: [dynamic]^doc.Entity

	for entry in array(pkg.entries) {
		check_proc :: proc(e: ^doc.Entity, parent: ^doc.Entity, is_output: bool) -> (related_proc: ^doc.Entity, ok: bool) {
			if e.kind != .Procedure {
				return
			}

			parent_name := str(parent.name)

			pt := base_type(cfg.types[e.type])
			(pt.kind == .Proc) or_return
			params := array(cfg.types[array(pt.types)[int(is_output)]].entities)
			for param_idx in params {
				t := cfg.types[cfg.entities[param_idx].type]
				#partial switch t.kind {
				case .Named, .Generic:
					// okay
				case .Pointer, .Multi_Pointer:
					t = cfg.types[array(t.types)[0]]
				case:
					continue
				}

				#partial switch t.kind {
				case .Named:
					named_entity := &cfg.entities[array(t.entities)[0]]
					if parent == named_entity {
						return e, true
					}

					gt_name, sep, _ := strings.partition(str(named_entity.name), "(")
					if sep == "(" && gt_name == parent_name {
						return e, true
					}
				case .Generic:
					type_types := array(t.types)
					if len(type_types) != 1 {
						continue
					}
					gt := cfg.types[type_types[0]]
					if gt.kind != .Named {
						continue
					}

					gt_name, sep, _ := strings.partition(str(gt.name), "(")
					if sep == "(" && gt_name == parent_name {
						return e, true
					}
				}
			}
			return
		}

		e := &cfg.entities[entry.entity]
		#partial switch e.kind {
		case .Procedure:
			if strings.has_prefix(str(e.name), "_") {
				continue
			}
			if p, ok := check_proc(e, parent, false); ok {
				append(&related_procs_in_parameters, p)
			}
			if !is_inherited {
				if p, ok := check_proc(e, parent, true); ok {
					append(&related_procs_in_return_types, p)
				}
			}
		case .Proc_Group:
			if strings.has_prefix(str(e.name), "_") {
				continue
			}
			for entity_idx in array(e.grouped_entities) {
				pe := &cfg.entities[entity_idx]
				if _, ok := check_proc(pe, parent, false); ok {
					append(&related_procs_in_parameters, e)
					break
				}
			}
			if !is_inherited do for entity_idx in array(e.grouped_entities) {
				pe := &cfg.entities[entity_idx]
				if _, ok := check_proc(pe, parent, true); ok {
					append(&related_procs_in_return_types, e)
					break
				}
			}
		}
	}

	the_sort_proc :: proc(a, b: ^doc.Entity) -> (cmp: slice.Ordering) {
		cmp = slice.cmp(a.kind, b.kind)
		if cmp != .Equal { return }
		cmp = slice.cmp(str(a.name), str(b.name))
		return
	}

	slice.sort_by_cmp(related_procs_in_parameters[:],   the_sort_proc)
	slice.sort_by_cmp(related_procs_in_return_types[:], the_sort_proc)

	print_procs :: proc(w:               io.Writer,
	                    pkg:             ^doc.Pkg,
	                    parent:          ^doc.Entity,
	                    related_procs:   []^doc.Entity,
	                    proc_names_seen: ^map[string]bool,
	                    is_inherited:    bool,
	                    title:           string) {
		parent_name := str(parent.name)
		seen_item := false
		parameter_loop: for e in related_procs {
			proc_name := str(e.name)

			if proc_names_seen[proc_name] {
				continue parameter_loop
			}

			collection := cfg.pkg_to_collection[pkg]

			proc_names_seen[proc_name] = true
			if !seen_item {
				if is_inherited {
					fmt.wprintf(
						w,
						"<h6>Procedures Through `using` From "+`<a href="%s/%s/#%s">%s</a></h6>`,
						collection.base_url,
						collection.pkg_to_path[pkg],
						parent_name,
						parent_name,
					)
					fmt.wprintln(w)
				} else {
					fmt.wprintf(w, "<h5>%s</h5>\n", title)
				}
				fmt.wprintln(w, "<ul>")
				seen_item = true
			}

			fmt.wprintf(w, "<li>")
			fmt.wprintf(
				w,
				`<a href="%s/%s/#%s">%s</a>`,
				collection.base_url,
				collection.pkg_to_path[pkg],
				proc_name,
				proc_name,
			)

			if e.kind == .Proc_Group {
				fmt.wprintf(w, `&nbsp;<em>(procedure groups)</em>`)
			}

			fmt.wprintf(w, "</li>")

			fmt.wprintln(w)
		}

		if seen_item {
			fmt.wprintln(w, "</ul>")
		}
	}

	print_procs(w, pkg, parent, related_procs_in_parameters[:],   proc_names_seen, is_inherited, title="Related Procedures With Parameters")
	print_procs(w, pkg, parent, related_procs_in_return_types[:], proc_names_seen, is_inherited, title="Related Procedures With Returns")

	delete(related_procs_in_parameters)
	delete(related_procs_in_return_types)

	{ // recursive_inheritance_check
		parent_type := cfg.types[parent.type]
		for parent_type.kind == .Named {
			parent_type = cfg.types[array(parent_type.types)[0]]
		}
		if parent_type.kind != .Struct {
			return
		}
		for entity_index in array(parent_type.entities) {
			field := &cfg.entities[entity_index]
			if .Param_Using not_in field.flags {
				continue
			}
			field_type := cfg.types[field.type]
			if field_type.entities.length == 0 {
				continue
			}
			field_type_entity := &cfg.entities[array(field_type.entities)[0]]
			field_pkg := &cfg.pkgs[cfg.files[field.pos.file].pkg]
			write_related_procedures(w, field_pkg, field_type_entity, proc_names_seen, true)
		}
	}
}

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

		this_pkg := &cfg.pkgs[cfg.files[entity.pos.file].pkg]
		if .Builtin_Pkg_Builtin in entity.flags {
			fmt.wprintf(w, `<a href="/base/builtin#{0:s}">builtin</a>.{0:s}`, name)
			return
		} else if .Builtin_Pkg_Intrinsics in entity.flags {
			fmt.wprintf(w, `<a href="/base/intrinsics#{0:s}">intrinsics</a>.{0:s}`, name)
			return
		} else if pkg != this_pkg {
			fmt.wprintf(w, "%s.", str(this_pkg.name))
		}
		collection := cfg.pkg_to_collection[this_pkg]

		class := ""
		if entity.kind == .Procedure {
			class = "code-procedure"
		}

		fmt.wprintf(w, `<a class="{3:s}" href="{2:s}/{0:s}/#{1:s}">`, collection.pkg_to_path[this_pkg], name, collection.base_url, class)
		io.write_string(w, name)
		io.write_string(w, `</a>`)
	}

	name := str(entry.name)
	e := &cfg.entities[entry.entity]
	entity_name := str(e.name)


	entity_pkg_index := cfg.files[e.pos.file].pkg
	entity_pkg := &cfg.pkgs[entity_pkg_index]
	writer := &Type_Writer{
		w = w,
		pkg = doc.Pkg_Index(intrinsics.ptr_sub(pkg, &cfg.pkgs[0])),
	}
	defer delete(writer.generic_scope)
	collection := cfg.pkg_to_collection[pkg]

	path := collection.pkg_to_path[pkg]
	filename := slashpath.base(str(cfg.files[e.pos.file].name))
	fmt.wprintf(w, "<h3 id=\"{0:s}\"><span><a class=\"doc-id-link\" href=\"#{0:s}\">{0:s}", name)
	fmt.wprintf(w, "<span class=\"a-hidden\">&nbsp;¶</span></a></span>")
	if e.pos.file != 0 && e.pos.line > 0 {
		src_url := fmt.tprintf("%s/%s/%s#L%d", collection.source_url, path, filename, e.pos.line)
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
			the_type := cfg.types[e.type]

			init_string := escape_html_string(str(e.init_string))
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

			if is_type_string_or_rune(the_type) {
				switch init_string[0] {
				case '"', '`', '\'':
					io.write_string(w, "<span class=\"string\">")
					io.write_string(w, init_string)
					io.write_string(w, "</span>")
				case:
					io.write_string(w, init_string)
				}
			} else {
				io.write_string(w, init_string)
			}
			fmt.wprintln(w, "</pre>")
		case .Variable:
			fmt.wprint(w, `<pre class="doc-code">`)
			write_attributes(w, e)
			fmt.wprintf(w, "%s: ", name)
			write_type(writer, cfg.types[e.type], {.Allow_Indent})
			init_string := str(e.init_string)
			if init_string != "" {
				io.write_string(w, " = ")
				io.write_string(w, "…")
			}
			fmt.wprintln(w, "</pre>")

		case .Type_Name:
			fmt.wprint(w, `<pre class="doc-code">`)
			defer fmt.wprintln(w, "</pre>")

			// write_attributes(w, e)
			fmt.wprintf(w, "%s :: ", name)
			the_type := cfg.types[e.type]
			type_to_print := the_type
			if base_type(type_to_print).kind == .Basic && str(pkg.name) == "c" {
				io.write_string(w, str(e.init_string))
				break
			}

			if the_type.kind == .Named && .Type_Alias not_in e.flags {
				if e.pos == cfg.entities[array(the_type.entities)[0]].pos {
					bt := base_type(the_type)
					#partial switch bt.kind {
					case .Struct, .Union, .Proc, .Enum:
						// Okay
					case:
						io.write_string(w, `<span class="keyword-type">distinct</span> `)
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
			write_type(writer, cfg.types[e.type], {.Allow_Multiple_Lines})
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
			fmt.wprintf(w, "%s :: <span class=\"keyword-type\">proc</span>{{\n", name)
			for entity_index in array(e.grouped_entities) {
				this_proc := &cfg.entities[entity_index]
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
	} else if e.kind == .Type_Name {
		proc_names_seen: map[string]bool
		write_related_procedures(w, pkg, e, &proc_names_seen)
		write_related_constants(w, pkg, e)
		delete(proc_names_seen)
	}
}

write_pkg :: proc(w: io.Writer, dir, path: string, pkg: ^doc.Pkg, collection: ^Collection, pkg_entries: Pkg_Entries) {
	fmt.wprintln(w, `<div class="row odin-main my-4" id="pkg">`)
	defer fmt.wprintln(w, `</div>`)

	write_pkg_sidebar(w, pkg, collection, str(pkg.name))

	fmt.wprintln(w, `<article class="col-lg-8 p-4 documentation odin-article">`)

	write_breadcrumbs(w, path, pkg, collection)

	fmt.wprintf(w, "<h1>package %s", strings.to_lower(collection.name, context.temp_allocator))

	// Is empty when the collection and package are at the same root path.
	collection_root_is_package := path == ""

	if !collection_root_is_package {
		fmt.wprintf(w, ":%s", path)
	}

	pkg_src_url := fmt.tprintf("%s/%s", collection.source_url, path)
	fmt.wprintf(w, "<div class=\"doc-source\"><a href=\"{0:s}\"><em>Source</em></a></div>", pkg_src_url)
	fmt.wprintf(w, "</h1>\n")

	if specific_target, ok := target_from_pkg(pkg); ok {
		fmt.wprintf(w, "<h4><strong>Warning:&nbsp;</strong>This was generated for <code>-target:%s</code> and might not represet every target this package supports.</h4>", specific_target)
	}

	// When this is the case, the collection page does not exists, so show license here.
	if collection_root_is_package {
		write_license(w, collection)
	}

	write_search(w, .Package)

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
				fmt.wprintf(w, "<li><a href=\"#{0:s}\">{0:s}</a></li>\n", str(e.name))
			}
			fmt.wprintln(w, "</ul>")
		}
	}

	for eo in pkg_entries.ordering {
		write_index(w, eo.name, eo.entries)
	}

	fmt.wprintln(w, "</div>")
	fmt.wprintln(w, "</div>")



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

	fmt.wprintln(w, `<section class="documentation">`)
	for eo in pkg_entries.ordering {
		write_entries(w, pkg, eo.name, eo.entries)
	}
	fmt.wprintln(w, "</section>")

	fmt.wprintln(w, `<h2 id="pkg-source-files">Source Files</h2>`)
	fmt.wprintln(w, "<ul>")
	any_hidden := false
	source_file_loop: for file_index in array(pkg.files) {
		file := cfg.files[file_index]
		filename := slashpath.base(str(file.name))
		switch {
		case
			strings.has_suffix(filename, "_windows.odin"),
			strings.has_suffix(filename, "_darwin.odin"),
			strings.has_suffix(filename, "_essence.odin"),
			strings.has_suffix(filename, "_haiku.odin"),
			strings.has_suffix(filename, "_freebsd.odin"),
			strings.has_suffix(filename, "_wasi.odin"),
			strings.has_suffix(filename, "_js.odin"),
			strings.has_suffix(filename, "_freestanding.odin"),

			strings.has_suffix(filename, "_amd64.odin"),
			strings.has_suffix(filename, "_i386.odin"),
			strings.has_suffix(filename, "_arch64.odin"),
			strings.has_suffix(filename, "_wasm32.odin"),
			strings.has_suffix(filename, "_wasm64.odin"),
			strings.has_suffix(filename, "_wasm64p32.odin"),
			false:
			any_hidden = true
			continue source_file_loop
		}
		fmt.wprintf(w, `<li><a href="%s/%s/%s">%s</a></li>`, collection.source_url, path, filename, filename)
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
