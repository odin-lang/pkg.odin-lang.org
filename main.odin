#+feature using-stmt
package odin_html_docs

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:io"
import "core:log"
import "core:os"
import "core:path/slashpath"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"
import "core:unicode"

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

	build_doc_link_index()


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

		init_pkg_entries_map(collection, collection.root)

		strings.builder_reset(&b)
		write_html_header(w, fmt.tprintf("%s library - pkg.odin-lang.org", dir), .Full_Width,
		                  description = fmt.tprintf("Package documentation for the Odin %s collection.", dir))
		write_collection_directory(w, collection)
		write_html_footer(w, "/pkg-data.js")
		os.make_directory(dir)
		_ = os.write_entire_file(fmt.tprintf("%s/index.html", dir), b.buf[:])

		generate_packages_in_collection(&b, collection)
	}


	{

		strings.builder_reset(&b)
		write_html_header(w, "Packages - pkg.odin-lang.org",
		                  description = "Browse API documentation for the Odin base, core, and vendor library collections.")
		write_home_page(w)
		write_html_footer(w, "/pkg-data.js")
		_ = os.write_entire_file("index.html", b.buf[:])
	}


	log.infof("generate json pkg data")
	generate_json_pkg_data(&b, not_hidden[:])

	log.infof("generate sitemap")
	generate_sitemap(&b, not_hidden[:])

	log.infof("generate 404")
	generate_404(&b)

	log.infof("generate moved package redirects")
	generate_moved_redirects(&b)

	log.infof("copy_assets")
	copy_assets()

	if doc_warning_count > 0 {
		log.warnf("%d documentation warnings", doc_warning_count)
	}

	log.infof("[DONE]")
}

generate_sitemap :: proc(b: ^strings.Builder, collections: []^Collection) {
	write_url :: proc(w: io.Writer, loc, lastmod: string) {
		fmt.wprintf(w, "\t<url><loc>%s</loc><lastmod>%s</lastmod></url>\n", loc, lastmod)
	}
	if cfg.domain == "" {
		log.warn("no `domain` configured; skipping sitemap.xml and robots.txt")
		return
	}
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	origin := fmt.tprintf("https://%s", cfg.domain)
	w := strings.to_writer(b)

	lastmod := build_date()

	strings.builder_reset(b)
	io.write_string(w, `<?xml version="1.0" encoding="UTF-8"?>`+"\n")
	io.write_string(w, `<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">`+"\n")

	write_url(w, fmt.tprintf("%s/", origin), lastmod)

	for c in collections {
		if c.hidden {
			continue
		}
		write_url(w, fmt.tprintf("%s%s/", origin, c.base_url), lastmod)
		if c.name == "base" {
			write_url(w, fmt.tprintf("%s%s/builtin/", origin, c.base_url), lastmod)
			write_url(w, fmt.tprintf("%s%s/intrinsics/", origin, c.base_url), lastmod)
		}

		paths := make([dynamic]string, 0, len(c.pkgs), context.temp_allocator)
		for path in c.pkgs {
			if path == "" { // package sitting at the collection root; already emitted above
				continue
			}
			append(&paths, path)
		}
		slice.sort(paths[:])
		for path in paths {
			write_url(w, fmt.tprintf("%s%s/%s/", origin, c.base_url, path), lastmod)
		}
	}

	io.write_string(w, "</urlset>\n")
	if nil != os.write_entire_file("sitemap.xml", b.buf[:]) {
		errorf("unable to write the sitemap.xml file")
	}

	strings.builder_reset(b)
	fmt.wprintln(w, "User-agent: *")
	fmt.wprintln(w, "Allow: /")
	fmt.wprintf(w, "Sitemap: %s/sitemap.xml\n", origin)
	if nil != os.write_entire_file("robots.txt", b.buf[:]) {
		errorf("unable to write the robots.txt file")
	}
}

generate_404 :: proc(b: ^strings.Builder) {
	strings.builder_reset(b)
	w := strings.to_writer(b)
	write_html_header(w, "404 Page not found - pkg.odin-lang.org",
		description = "The page you were looking for could not be found.")
	io.write_string(w, ```
		<div class="p-4">
			<h1>Page not found</h1>
			<p>The package or page you were looking for does not exist; it may have been moved or renamed.</p>
			<p><a href="/">Browse all packages</a> or search for it below.</p>
	```)
	write_search(w, .All)
	io.write_string(w, "</div>\n")

	// NOTE(bill): search.js fills the search with the last part of the missing path
	io.write_string(w, "<script>var odin_not_found = true;</script>\n")
	write_html_footer(w, "/pkg-data.js")
	_ = os.write_entire_file("404.html", b.buf[:])
}

generate_moved_redirects :: proc(b: ^strings.Builder) {
	find :: proc(import_path: string) -> (collection: ^Collection, path: string, ok: bool) {
		name, _, rest := strings.partition(import_path, ":")
		for c in cfg.collections {
			if c.name == name {
				return c, rest, rest != ""
			}
		}
		return
	}

	for old, new in cfg.moved_packages {
		old_collection, old_path, old_ok := find(old)
		new_collection, new_path, new_ok := find(new)
		if !old_ok || !new_ok || new_path not_in new_collection.pkgs {
			log.warnf("moved_packages: cannot redirect %q to %q", old, new)
			continue
		}
		if old_path in old_collection.pkgs {
			continue // it is there again
		}

		url := fmt.tprintf("%s/%s/", new_collection.base_url, new_path)
		strings.builder_reset(b)
		fmt.sbprintf(b, ```
			<!doctype html>
			<html lang="en">
			<head>
			<meta charset="utf-8">
			<title>package {0:s} moved to {1:s} - pkg.odin-lang.org</title>
			<link rel="canonical" href="{2:s}">
			<meta name="robots" content="noindex">
			<meta http-equiv="refresh" content="0; url={2:s}">
			<script>location.replace("{2:s}" + location.hash)</script>
			</head>
			<body>
			<p>Package <code>{0:s}</code> has moved to <a href="{2:s}"><code>{1:s}</code></a>.</p>
			</body>
			</html>
			```,
			old, new, url)
		recursive_make_directory(old_path, old_collection.name)
		_ = os.write_entire_file(fmt.tprintf("%s/%s/index.html", old_collection.name, old_path), b.buf[:])
	}
}


@(require_results)
build_time :: proc() -> time.Time {
	@(static)
	_build_time: Maybe(time.Time)

	if t, ok := _build_time.?; ok {
		return t
	}
	t := time.now()
	if s := os.get_env("SOURCE_DATE_EPOCH", context.temp_allocator); s != "" {
		if secs, ok := strconv.parse_i64(s); ok {
			t = time.unix(secs, 0)
		}
	}
	_build_time = t
	return t
}
@(require_results)
build_date :: proc() -> string {
	y, m, d := time.date(build_time())
	return fmt.tprintf("%04d-%02d-%02d", y, int(m), int(d))
}

init_cfg_from_header :: proc(header: ^doc.Header, loc := #caller_location) {
	assert(header != nil, loc=loc)
	cfg.header   = header
	cfg.files    = array(cfg.header.files)
	cfg.pkgs     = array(cfg.header.pkgs)
	cfg.entities = array(cfg.header.entities)
	cfg.types    = array(cfg.header.types)

	for &pkg in cfg.pkgs {
		for &entry in array(pkg.entries) {
			cfg.entity_to_pkg[&cfg.entities[entry.entity]] = &pkg
		}
	}
}
init_cfg_from_pkg :: proc(pkg: ^doc.Pkg, loc := #caller_location) {
	assert(pkg != nil, loc=loc)
	init_cfg_from_header(cfg.pkg_to_header[pkg], loc)
}


generate_from_path :: proc(path: string, all_packages: bool) {
	log.debugf("reading %q", path)

	{
		data, data_err := os.read_entire_file(path, context.allocator)
		if data_err != nil {
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
			log.debugf(```
				Collection %q configured with:
					Source URL: %s
					Base URL: %s
					Root Path: %s
					License: %s at %s
					Hidden: %v
					Home:
						Title: %s
						Description: %s
						Readme: %s
				```,
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
				if cfg.handled_packages[fp] >= len(array(pkg.entries)) {
					log.debugf("package already handled: %q", fp)
					continue
				} else {
					log.debugf("package already handled but this instance has more entries: %q", fp)
				}
			} else {
				log.debugf("new package: %q", fp)
			}

			append(&pkgs, &pkg)
			cfg.handled_packages[fp] = len(array(pkg.entries))
			cfg.pkg_to_header[&pkg] = cfg.header
		}

		log.infof("%d packages - %s", len(pkgs), path)

		fullpath_loop: for pkg in pkgs {
			fullpath := str(pkg.fullpath)
			if len(array(pkg.entries)) == 0 && strings.trim_space(str(pkg.docs)) == "" {
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

			collection.pkgs[trimmed] = pkg
			collection.pkg_to_path[pkg] = trimmed
			cfg.pkg_to_collection[pkg] = collection
			cfg.pkg_to_header[pkg] = cfg.header
			cfg.name_to_pkg[str(pkg.name)] = pkg
		}

		collection_pkgs: [dynamic]^doc.Pkg
		defer delete(collection_pkgs)
		for c in cfg.collections {
			if c.root == nil {
				assert(all_packages)
				c.root = new(Dir_Node)
				c.root.children = make([dynamic]^Dir_Node)
			}

			clear(&collection_pkgs)
			for pkg in pkgs {
				if pkg in c.pkg_to_path {
					append(&collection_pkgs, pkg)
				}
			}

			insert_into_directory_tree(c, collection_pkgs)
		}
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
	if nil != os.write_entire_file("search.js", #load("resources/search.js")) {
		errorf("unable to write the search.js file")
	}

	if nil != os.write_entire_file("style.css", #load("resources/style.css")) {
		errorf("unable to write the style.css file")
	}

	if nil != os.write_entire_file("favicon.svg", #load("resources/favicon.svg")) {
		errorf("unable to write favicon.svg file")
	}
}

write_head_meta :: proc(w: io.Writer, title, description: string) {
	write_attr_value :: proc(w: io.Writer, s: string, max_len := 0) {
		pending_space := false
		started := false
		count := 0
		for r in s {
			if strings.is_space(r) {
				if started {
					pending_space = true
				}
				continue
			}
			if max_len > 0 && count >= max_len {
				io.write_string(w, "…")
				return
			}
			if pending_space {
				io.write_byte(w, ' ')
				count += 1
				pending_space = false
			}
			started = true
			switch r {
			case '&':  io.write_string(w, "&amp;")
			case '<':  io.write_string(w, "&lt;")
			case '>':  io.write_string(w, "&gt;")
			case '"':  io.write_string(w, "&quot;")
			case '\'': io.write_string(w, "&#39;")
			case:      io.write_rune(w, r)
			}
			count += 1
		}
	}

	tag :: proc(w: io.Writer, attr, name, content: string, max_len := 0) {
		fmt.wprintf(w, "\n<meta %s=\"%s\" content=\"", attr, name)
		write_attr_value(w, content, max_len)
		io.write_string(w, "\">")
	}
	io.write_string(w, `<meta property="og:type" content="website">`)
	tag(w, "name",     "description",         description, 200)
	tag(w, "property", "og:title",            title)
	tag(w, "property", "og:description",      description, 200)
	tag(w, "name",     "twitter:card",        "summary")
	tag(w, "name",     "twitter:title",       title)
	tag(w, "name",     "twitter:description", description, 200)
	io.write_string(w, "\n")
}


Header_Kind :: enum {
	Normal,
	Full_Width,
}

write_html_header :: proc(w: io.Writer, title: string, kind := Header_Kind.Normal, description := "") {
	fmt.wprintf(w, string(#load("resources/header.txt.html")), title)

	when #config(ODIN_DOC_DEV, false) {
		io.write_string(w, "\n")
		io.write_string(w, `<script type="text/javascript" src="https://livejs.com/live.js"></script>`)
		io.write_string(w, "\n")
	}

	if description != "" {
		write_head_meta(w, title, description)
	}


	io.write(w, #load("resources/header-lower.txt.html"))
	switch kind {
	case .Normal:
		io.write_string(w, `<div class="container">`+"\n")
	case .Full_Width:
		io.write_string(w, `<div class="container full-width">`+"\n")
	}
}

// "/pkg-data.js" holds every package for the global search on the home and collection pages
generate_json_pkg_data :: proc(b: ^strings.Builder, collections: []^Collection) {
	w := strings.to_writer(b)

	strings.builder_reset(b)
	now := build_time()
	fmt.wprintf(w, "/** Generated with odin version %s (vendor %q) %s_%s @ %v */\n", ODIN_VERSION, ODIN_VENDOR, ODIN_OS, ODIN_ARCH, now)
	pkg_data_begin(w)


	base_collection: ^Collection
	for c in collections {
		if c.name == "base" {
			base_collection = c
			break
		}
	}

	pkg_idx := 0
	if base_collection != nil {
		write_pkg_data_builtins(w, base_collection, "builtin", builtins)
		fmt.wprintln(w, ",")
		write_pkg_data_builtins(w, base_collection, "intrinsics", intrinsics_table)
		pkg_idx += 2
	}


	for collection in collections {
		paths := make([dynamic]string, 0, len(collection.pkgs), context.temp_allocator)
		for path in collection.pkgs {
			append(&paths, path)
		}
		slice.sort(paths[:])
		for path in paths {
			if pkg_idx != 0 { fmt.wprintln(w, ",") }
			write_pkg_data_pkg(w, collection, path, collection.pkgs[path])
			pkg_idx += 1
		}
	}
	pkg_data_end(w)

	_ = os.write_entire_file("pkg-data.js", b.buf[:])
}

// Package pages only ever search their own package, so each gets a "pkg-data.js"
// beside its index.html with just that, rather than loading all of "/pkg-data.js"
pkg_data_url :: proc(collection: ^Collection, path: string) -> string {
	if path == "" {
		return fmt.tprintf("%s/pkg-data.js", collection.base_url)
	}
	return fmt.tprintf("%s/%s/pkg-data.js", collection.base_url, path)
}

pkg_data_begin :: proc(w: io.Writer) {
	fmt.wprint(w, "var odin_pkg_data = {\n")
	fmt.wprintln(w, `"packages": {`)
}

pkg_data_end :: proc(w: io.Writer) {
	fmt.wprintln(w, "}};")
}

// `name` is "builtin" or "intrinsics", and is also the flag set on each of their entities
write_pkg_data_builtins :: proc(w: io.Writer, collection: ^Collection, name: string, table: []Builtin) {
	fmt.wprintf(w, "\t\"%s\": {{\n", name)
	fmt.wprintf(w, "\t\t\"name\": \"%s\",\n", name)
	fmt.wprintf(w, "\t\t\"collection\": \"%s\",\n", collection.name)
	fmt.wprintf(w, "\t\t\"path\": \"%s/%s\",\n", collection.base_url, name)
	fmt.wprint(w, "\t\t\"entities\": [\n")

	for b, i in table {
		if i != 0 { fmt.wprint(w, ",\n") }
		fmt.wprint(w, "\t\t\t{")
		fmt.wprintf(w, `"kind": %q, `, b.kind)
		fmt.wprintf(w, `"name": %q, `, b.name)
		fmt.wprintf(w, `"type": %q, `, b.type)
		fmt.wprintf(w, `"%s": %v, `, name, true)
		if len(b.comment) != 0 {
			fmt.wprintf(w, `"comment": %q`, b.comment)
		}
		fmt.wprint(w, "}")
	}

	fmt.wprint(w, "\n\t\t]")
	fmt.wprint(w, "\n\t}")
}

write_pkg_data_pkg :: proc(w: io.Writer, collection: ^Collection, path: string, pkg: ^doc.Pkg, summaries := false) {
	init_cfg_from_pkg(pkg)
	entries := collection.pkg_entries_map[pkg]

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

		entity := &cfg.entities[e.entity]
		// so `MTLBuffer` finds `Buffer`
		if entity.kind == .Type_Name {
			if objc_class, ok := find_entity_attribute(entity, "objc_class"); ok {
				fmt.wprintf(w, `, "objc": %s`, objc_class)
			}
		}
		// and `SDL_CreateWindow` finds `CreateWindow`
		if c_name := entity_c_name(entity, str(e.name)); c_name != "" {
			fmt.wprintf(w, `, "c": %q`, c_name)
		}
		if _, ok := find_entity_attribute(entity, "deprecated"); ok {
			io.write_string(w, `, "dep": 1`)
		}
		if summaries {
			docs := str(entity.docs)
			if strings.trim_space(docs) == "" {
				docs = str(entity.comment)
			}
			if summary := doc_summary(docs); summary != "" {
				io.write_string(w, `, "d": `)
				write_json_string(w, summary)
			}
		}


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
}

write_html_footer :: proc(w: io.Writer, pkg_data_url: string) {
	io.write_string(w, "\n")

	io.write(w, #load("resources/footer.txt.html"))
	fmt.wprintf(w, `<script src="%s"></script>`+"\n", pkg_data_url)
	io.write_string(w, `<script src="/search.js"></script>`+"\n")
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
			line_doc := doc_summary_line(str(pkg.docs))
			cfg.pkgs_line_docs[strings.clone(str(pkg.fullpath))] = strings.clone(line_doc)
		}

		strings.builder_reset(b)
		w := strings.to_writer(b)

		desc := markdown_plain_text(cfg.pkgs_line_docs[str(pkg.fullpath)], context.temp_allocator)
		if desc == "" {
			desc = fmt.tprintf("API documentation for the Odin package %s.", path)
		}

		write_html_header(w, fmt.tprintf("package %s - pkg.odin-lang.org", path), .Full_Width, description = desc)
		write_pkg(w, dir, path, pkg, collection, collection.pkg_entries_map[pkg])
		write_html_footer(w, pkg_data_url(collection, path))
		recursive_make_directory(path, dir)
		_ = os.write_entire_file(fmt.tprintf("%s/%s/index.html", dir, path), b.buf[:])

		strings.builder_reset(b)
		pkg_data_begin(w)
		write_pkg_data_pkg(w, collection, path, pkg, summaries = true)
		pkg_data_end(w)
		_ = os.write_entire_file(fmt.tprintf("%s/%s/pkg-data.js", dir, path), b.buf[:])

		strings.builder_reset(b)
		write_type_previews(w)
		_ = os.write_entire_file(fmt.tprintf("%s/%s/types.json", dir, path), b.buf[:])
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

	runtime_pkg := generate_package_from_directory_tree(b, collection.root)

	if runtime_pkg != nil &&
	   collection.name == "base" {
		init_cfg_from_pkg(runtime_pkg)

		path := "builtin"

		strings.builder_reset(b)
		write_html_header(w, fmt.tprintf("package %s - pkg.odin-lang.org", path), .Full_Width,
		                  description = "Built-in procedures, types, and constants available in every Odin file.")
		write_builtin_pkg(w, dir, path, runtime_pkg, collection, "builtin", builtin_docs)
		write_html_footer(w, pkg_data_url(collection, path))
		recursive_make_directory(path, dir)
		_ = os.write_entire_file(fmt.tprintf("%s/%s/index.html", dir, path), b.buf[:])

		// the builtin page also searches the @(builtin) procedures of runtime
		strings.builder_reset(b)
		pkg_data_begin(w)
		write_pkg_data_builtins(w, collection, "builtin", builtins)
		fmt.wprintln(w, ",")
		write_pkg_data_pkg(w, collection, collection.pkg_to_path[runtime_pkg], runtime_pkg, summaries = true)
		pkg_data_end(w)
		_ = os.write_entire_file(fmt.tprintf("%s/%s/pkg-data.js", dir, path), b.buf[:])

		strings.builder_reset(b)
		write_type_previews(w)
		_ = os.write_entire_file(fmt.tprintf("%s/%s/types.json", dir, path), b.buf[:])

		path = "intrinsics"
		strings.builder_reset(b)
		write_html_header(w, fmt.tprintf("package %s - pkg.odin-lang.org", path), .Full_Width,
		                  description = "Compiler intrinsics provided by the Odin compiler.")
		write_builtin_pkg(w, dir, path, runtime_pkg, collection, "intrinsics", intrinsics_docs)
		write_html_footer(w, pkg_data_url(collection, path))
		recursive_make_directory(path, dir)
		_ = os.write_entire_file(fmt.tprintf("%s/%s/index.html", dir, path), b.buf[:])

		strings.builder_reset(b)
		pkg_data_begin(w)
		write_pkg_data_builtins(w, collection, "intrinsics", intrinsics_table)
		pkg_data_end(w)
		_ = os.write_entire_file(fmt.tprintf("%s/%s/pkg-data.js", dir, path), b.buf[:])

		strings.builder_reset(b)
		write_type_previews(w)
		_ = os.write_entire_file(fmt.tprintf("%s/%s/types.json", dir, path), b.buf[:])
	}
}

collection_stats :: proc(c: ^Collection) -> (packages, declarations: int) {
	for _, pkg in c.pkgs {
		packages += 1
		declarations += len(c.pkg_entries_map[pkg].all)
	}
	if c.name == "base" { // builtin and intrinsics are documented as packages of their own
		packages += 2
		declarations += len(builtins) + len(intrinsics_table)
	}
	return
}

// 12345 -> "12,345"
thousands :: proc(n: int) -> string {
	digits := fmt.tprintf("%d", n)
	b := strings.builder_make(context.temp_allocator)
	for c, i in digits {
		if i > 0 && (len(digits)-i) % 3 == 0 {
			strings.write_byte(&b, ',')
		}
		strings.write_rune(&b, c)
	}
	return strings.to_string(b)
}

write_home_page :: proc(w: io.Writer) {
	collections := make([dynamic]^Collection, 0, len(cfg.collections), context.temp_allocator)
	for c in cfg.collections {
		if cfg.hide_base && (c.name == "base") {
			continue
		}
		if cfg.hide_core && (c.name == "core" || c.name == "vendor") {
			continue
		}
		append(&collections, c)
	}

	total_packages, total_declarations: int
	for c in collections {
		packages, declarations := collection_stats(c)
		total_packages     += packages
		total_declarations += declarations
	}

	fmt.wprintln(w, `<div class="odin-home">`)
	defer fmt.wprintln(w, `</div>`)

	fmt.wprintln(w, `<header class="odin-home-hero">`)
	fmt.wprintln(w, `<h1>Odin Packages</h1>`)
	io.write_string(w, `<p class="odin-home-lead">API documentation for the `)
	for c, i in collections {
		if i > 0 {
			io.write_string(w, i+1 == len(collections) ? " and " : ", ")
		}
		fmt.wprintf(w, `<code>%s</code>`, c.name)
	}
	fmt.wprintf(w, " library collection%s.</p>\n", len(collections) == 1 ? "" : "s")
	write_search(w, .All, fmt.tprintf("Search %s declarations across %d packages.", thousands(total_declarations), total_packages))
	fmt.wprintln(w, `</header>`)

	fmt.wprintln(w, `<section class="odin-home-collections">`)
	for c in collections {
		packages, declarations := collection_stats(c)
		fmt.wprintln(w, `<div class="odin-collection-card">`)
		fmt.wprintf(w, `<h2><a href="%s">%s</a></h2>`+"\n", c.base_url, c.home.title.? or_else c.name)
		fmt.wprintf(w, `<div class="odin-collection-stats">%d packages &middot; %s declarations</div>`+"\n", packages, thousands(declarations))
		if d, ok := c.home.description.?; ok {
			fmt.wprintf(w, "<p>%s</p>\n", d)
		}
		fmt.wprintln(w, `</div>`)
	}
	fmt.wprintln(w, `</section>`)

	// a readme is too long for a card, so it goes below them
	for c in collections {
		if path, ok := c.home.embed_readme.?; ok {
			log.infof("Writing readme from path at: %s", path)
			fmt.wprintf(w, `<section class="odin-home-readme"><h2><a href="%s">%s</a></h2>`+"\n", c.base_url, c.home.title.? or_else c.name)
			write_readme(w, path)
			fmt.wprintln(w, `</section>`)
		}
	}
}

write_readme :: proc(w: io.Writer, path: string) {
	data, data_err := os.read_entire_file(path, context.allocator)
	if data_err != nil {
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
		case "darwin", "posix", "kqueue", "darwin/Foundation", "darwin/CoreFoundation", "darwin/Security":
			target = "darwin_arm64"
		case "linux", "unix":
			target = "linux_arm64"
		case "freebsd":
			target = "freebsd_amd64"
		case "wasm/js", "wasm/wasi":
			target = "js_wasm32"
		}
	}
	return
}


entity_c_name :: proc(e: ^doc.Entity, name: string) -> string {
	if .Foreign not_in e.flags || (e.kind != .Procedure && e.kind != .Variable) {
		return ""
	}
	link_name := str(e.link_name)
	// `system:Kernel32.lib..GetConsoleOutputCP` and `odin_env..abort` name their library first
	if n := strings.last_index(link_name, ".."); n >= 0 {
		link_name = link_name[n+2:]
	}
	if link_name == "" || link_name == name || link_name == str(e.name) {
		return ""
	}
	if _, ok := find_entity_attribute(e, "link_name"); ok {
		return ""
	}
	return link_name
}

parse_integer_literal :: proc(literal: string) -> (value: i128, ok: bool) {
	s := strings.trim_space(literal)
	negative := strings.has_prefix(s, "-")
	if negative {
		s = s[1:]
	}
	if s == "" || !('0' <= s[0] && s[0] <= '9') {
		return
	}
	digits, _ := strings.remove_all(s, "_", context.temp_allocator)
	value = strconv.parse_i128(digits) or_return
	return -value if negative else value, true
}

write_config_flag :: proc(w: io.Writer, init_string: string) {
	inner := strings.trim_space(init_string)
	if !strings.has_prefix(inner, "#config(") || !strings.has_suffix(inner, ")") {
		return
	}
	inner = inner[len("#config("):len(inner)-1]
	name, _, default := strings.partition(inner, ",")
	name, default = strings.trim_space(name), strings.trim_space(default)
	if name == "" {
		return
	}

	io.write_string(w, `<pre class="doc-code doc-code-usage">-define:`)
	io.write_string(w, name)
	io.write_byte(w, '=')
	// only a literal can be given to -define, so anything else is left for you to fill in
	switch {
	case default == "true" || default == "false":
		fmt.wprintf(w, `<span class="keyword">%s</span>`, default)
	case strings.has_prefix(default, `"`) && strings.has_suffix(default, `"`) && len(default) >= 2:
		fmt.wprintf(w, `<span class="string">%s</span>`, escape_html_string(default, context.temp_allocator))
	case:
		if _, ok := parse_integer_literal(default); ok {
			fmt.wprintf(w, `<span class="number">%s</span>`, default)
		} else {
			io.write_string(w, "&lt;value&gt;")
		}
	}
	io.write_string(w, "</pre>\n")
}

pkg_line_doc :: proc(pkg: ^doc.Pkg) -> (line_doc: string, ok: bool) {
	if pkg == nil {
		return
	}
	line_doc = cfg.pkgs_line_docs[str(pkg.fullpath)]
	if line_doc == "" {
		line_doc = doc_summary_line(str(pkg.docs))
	}

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

write_collection_directory :: proc(w: io.Writer, collection: ^Collection) {

	packages, declarations := collection_stats(collection)

	fmt.wprintln(w, `<div class="row odin-main odin-docs-layout my-4">`)
	defer fmt.wprintln(w, `</div>`)

	write_pkg_sidebar(w, nil, collection, "", "")

	fmt.wprintln(w, `<article class="col-lg-10 p-4">`)
	defer fmt.wprintln(w, `</article>`)

	fmt.wprintln(w, `<header class="odin-collection-header">`)
	fmt.wprintf(w, "<h1 style=\"text-transform: capitalize\">%s Library Collection</h1>\n", collection.name)
	if d, ok := collection.home.description.?; ok {
		fmt.wprintf(w, `<p class="odin-collection-lead">%s</p>`+"\n", d)
	}
	fmt.wprintln(w, `<ul class="odin-collection-meta">`)
	fmt.wprintf(w, `<li><span>License</span> <a href="%s">%s</a></li>`+"\n", collection.license.url, collection.license.text)
	fmt.wprintf(w, `<li><span>Source</span> <a href="%s">%s</a></li>`+"\n", collection.source_url, short_source_url(collection.source_url))
	fmt.wprintf(w, `<li><span>Packages</span> %d</li>`+"\n", packages)
	fmt.wprintf(w, `<li><span>Declarations</span> %s</li>`+"\n", thousands(declarations))
	fmt.wprintln(w, `</ul>`)
	write_search(w, .Collection)
	fmt.wprintln(w, `</header>`)

	fmt.wprintf(w, `<h2 id="pkg-list" class="odin-pkg-list-title">Packages <span class="pkg-count">%d</span></h2>`+"\n", packages)
	fmt.wprintln(w, `<table class="odin-pkg-table">`)
	defer fmt.wprintln(w, `</table>`)

	write_directory :: proc(w: io.Writer, dir: ^Dir_Node, collection: ^Collection) {
		children := 0
		for child in dir.children {
			children += int(str(child.pkg.name) != "os2")
		}

		if len(dir.children) != 0 {
			fmt.wprintf(w, `<tbody class="pkg-group"><tr id="pkg-%s" class="pkg-group-head"><td class="pkg-name">`, dir.dir)
		} else {
			fmt.wprintf(w, `<tbody><tr id="pkg-%s"><td class="pkg-name">`, dir.dir)
		}
		defer io.write_string(w, "</tbody>\n")

		if dir.pkg != nil {
			init_cfg_from_pkg(dir.pkg)
			fmt.wprintf(w, `<a href="%s/%s">%s</a>`, collection.base_url, dir.path, dir.name)
		} else if dir.name == "builtin" || dir.name == "intrinsics" {
			fmt.wprintf(w, `<a href="%s/%s">%s</a>`, collection.base_url, dir.path, dir.name)
		} else {
			fmt.wprintf(w, `<span class="pkg-group-label">%s</span>`, dir.name)
		}
		io.write_string(w, `</td>`)
		io.write_string(w, `<td class="pkg-desc">`)
		switch dir.name {
		case "builtin":
			first, _, _ := strings.partition(builtin_docs, ".")
			write_doc_line(w, first)
			io.write_string(w, `.`)
		case "intrinsics":
			first, _, _ := strings.partition(intrinsics_docs, ".")
			write_doc_line(w, first)
			io.write_string(w, `.`)
		case  "runtime":
			first := "package runtime provides all of the declarations needed by all Odin code-bases"
			write_doc_line(w, first)
			io.write_string(w, `.`)
		case "sanitizer":
			first := "package sanitizer implements various procedures for interacting with sanitizers from user code"
			write_doc_line(w, first)
			io.write_string(w, `.`)
		case:
			if line_doc, ok := pkg_line_doc(dir.pkg); ok {
				write_doc_line(w, line_doc, dir.pkg)
			} else if dir.dir == "sys" {
				io.write_string(w, `Platform specific packages - documentation may be for a specific platform only`)
			}
		}
		if len(dir.children) != 0 {
			fmt.wprintf(w, ` <span class="pkg-count">%d package%s</span>`, children, children == 1 ? "" : "s")
		}
		io.write_string(w, `</td>`)
		// builtin is the only one of these that cannot be imported
		write_copy_import(w, collection, dir.path, dir.pkg, dir.pkg != nil || dir.name == "intrinsics")
		fmt.wprintf(w, "</tr>\n")

		for child in dir.children {
			assert(child.pkg != nil)
			init_cfg_from_pkg(child.pkg)

			if str(child.pkg.name) == "os2" {
				continue
			}

			fmt.wprintf(w, `<tr id="pkg-%s" class="pkg-child"><td class="pkg-name">`, child.name)
			fmt.wprintf(w, `<a href="%s/%s/">%s</a>`, collection.base_url, child.path, child.name)
			io.write_string(w, `</td>`)

			io.write_string(w, `<td class="pkg-desc">`)
			if child_line_doc, ok := pkg_line_doc(child.pkg); ok {
				write_doc_line(w, child_line_doc, child.pkg)
			} else if target, target_ok := target_from_pkg(child.pkg); target_ok {
				fmt.wprintf(w, `<em>(Generated with <code>-target:%s</code>, please read the source code directly)</em>`, target)
			}
			io.write_string(w, `</td>`)
			write_copy_import(w, collection, child.path, child.pkg, true)
			fmt.wprintf(w, "</tr>\n")
		}
	}

	write_copy_import :: proc(w: io.Writer, collection: ^Collection, path: string, pkg: ^doc.Pkg, importable: bool) {
		io.write_string(w, `<td class="pkg-import">`)
		if importable {
			write_copy_import_button(w, collection, path, pkg, "import")
		}
		io.write_string(w, `</td>`)
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
}

// "https://github.com/odin-lang/Odin/tree/master/core" -> "odin-lang/Odin/core"
short_source_url :: proc(url: string) -> string {
	s := strings.trim_prefix(strings.trim_prefix(url, "https://"), "http://")
	if !strings.has_prefix(s, "github.com/") {
		return s
	}
	s = s[len("github.com/"):]
	parts := strings.split(s, "/", context.temp_allocator)
	if len(parts) < 4 || parts[2] != "tree" {
		return s
	}
	// drop the "tree/<branch>" between the repository and the path
	path := strings.join(parts[4:], "/", context.temp_allocator)
	if path == "" {
		return fmt.tprintf("%s/%s", parts[0], parts[1])
	}
	return fmt.tprintf("%s/%s/%s", parts[0], parts[1], path)
}

import_declaration :: proc(collection: ^Collection, path: string, pkg: ^doc.Pkg) -> (name, import_path: string) {
	is_identifier :: proc(s: string) -> bool {
		for r, i in s {
			if !(r == '_' || unicode.is_letter(r) || (i > 0 && unicode.is_digit(r))) {
				return false
			}
		}
		return s != ""
	}

	import_path = fmt.tprintf("%s:%s", collection.name, path)
	if alias, ok := cfg.import_aliases[import_path]; ok {
		name = alias
	} else if !is_identifier(slashpath.base(path)) && pkg != nil {
		name = str(pkg.name)
	}
	return
}

// e.g. "core:sys/darwin/Foundation"
pkg_import_path :: proc(pkg: ^doc.Pkg) -> string {
	collection := cfg.pkg_to_collection[pkg]
	if collection == nil {
		return ""
	}
	return fmt.tprintf("%s:%s", collection.name, collection.pkg_to_path[pkg])
}

pkg_import_name :: proc(pkg: ^doc.Pkg) -> string {
	@(static) names: map[^doc.Pkg]string
	if name, ok := names[pkg]; ok {
		return name
	}
	name := cfg.import_aliases[pkg_import_path(pkg)] or_else str(pkg.name)
	names[pkg] = name
	return name
}

write_copy_import_button :: proc(w: io.Writer, collection: ^Collection, path: string, pkg: ^doc.Pkg, label: string) {
	name, import_path := import_declaration(collection, path, pkg)
	io.write_string(w, `<button type="button" class="copy-import" data-copy="import `)
	if name != "" {
		fmt.wprintf(w, "%s ", name)
	}
	fmt.wprintf(w, `&quot;%s&quot;" title="Copy the import declaration" aria-label="Copy the import declaration">%s</button>`, import_path, label)
}

pkg_listed_files :: proc(pkg: ^doc.Pkg) -> (files: [dynamic]string, any_hidden: bool) {
	files = make([dynamic]string, context.temp_allocator)
	for file_index in array(pkg.files) {
		filename := slashpath.base(str(cfg.files[file_index].name))
		switch {
		case
			strings.has_suffix(filename, "_windows.odin"),
			strings.has_suffix(filename, "_darwin.odin"),
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
		case:
			append(&files, filename)
		}
	}
	return
}

// The line under a package's title, like the one on the collection pages
write_pkg_meta :: proc(w: io.Writer, collection: ^Collection, path: string, pkg: ^doc.Pkg, importable: bool, src_url: string, files, declarations: int) {
	fmt.wprintln(w, `<ul class="odin-collection-meta odin-pkg-meta">`)
	if importable {
		name, import_path := import_declaration(collection, path, pkg)
		io.write_string(w, `<li><code class="odin-import"><span class="keyword">import</span> `)
		if name != "" {
			fmt.wprintf(w, "%s ", name)
		}
		fmt.wprintf(w, `<span class="string">&quot;%s&quot;</span></code> `, import_path)
		write_copy_import_button(w, collection, path, pkg, "copy")
		io.write_string(w, "</li>\n")
	}
	fmt.wprintf(w, `<li><span>Source</span> <a href="%s">%s</a></li>`+"\n", src_url, short_source_url(src_url))
	if files > 0 {
		fmt.wprintf(w, `<li><span>Files</span> %d</li>`+"\n", files)
	}
	fmt.wprintf(w, `<li><span>Declarations</span> %s</li>`+"\n", thousands(declarations))
	fmt.wprintln(w, `</ul>`)
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
		io.write_string(w, " <span class=\"keyword\">where</span> ")
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
	Force_Multiple_Lines,
}

Write_Type_Flags :: distinct bit_set[Write_Type_Flag]

Type_Writer :: struct {
	w:      io.Writer,
	pkg:    doc.Pkg_Index,
	indent: int,
	generic_scope: map[string]bool,
}

MAX_SIGNATURE_WIDTH :: 100

visible_width :: proc(html: string) -> (width: int) {
	in_tag, in_entity := false, false
	for r in html {
		switch {
		case in_tag:
			in_tag = r != '>'
		case in_entity:
			in_entity = r != ';'
		case r == '<':
			in_tag = true
		case r == '&':
			in_entity = true
			width += 1
		case:
			width += 1
		}
	}
	return
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
			if .Param_Ellipsis == flag {
				continue
			}
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
			type_flags := flags
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
					if init_string != "" {
						io.write_string(w, " = ")
						io.write_string(w, init_string)
					}
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
			io.write_string(w, strip_doxygen_brief(line))
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
		io.write_string(w, strings.trim_right_space(strip_doxygen_brief(comment)))
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
		} else if str(cfg.pkgs[tn_pkg].name) == "" {
			// e.g. `objc_class`, from base:intrinsics, which has no package of its own here
			fmt.wprintf(w, `intrinsics.<a class="code-typename" href="/base/intrinsics#{0:s}">{0:s}</a>`, name)
			break
		}

		if tn_pkg != pkg {
			// remove the extra prefix e.g. `foo.foo.bar`
			name_prefix := name
			if n := strings.index_byte(name_prefix, '('); n >= 0 {
				name_prefix = name_prefix[:n]
			}
			if !strings.contains_rune(name_prefix, '.') {
				fmt.wprintf(w, `%s.`, pkg_import_name(&cfg.pkgs[tn_pkg]))
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
		if name not_in generic_scope && .Is_Results not_in flags {
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
		io.write_string(w, `[<span class="number">`)
		if len(type_types) >= 2 {
			write_type(writer, cfg.types[type_types[1]], flags)
		} else {
			io.write_uint(w, uint(type.elem_counts[0]))
		}
		io.write_string(w, `</span>]`)
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
	case .Fixed_Capacity_Dynamic_Array:
		assert(type.elem_count_len == 1)
		io.write_string(w, "[<span class=\"keyword\">dynamic</span>; ")
		if len(type_types) >= 2 {
			write_type(writer, cfg.types[type_types[1]], flags)
		} else {
			io.write_uint(w, uint(type.elem_counts[0]))
		}
		io.write_string(w, "]")
		write_type(writer, cfg.types[type_types[0]], flags)
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

		if type.polymorphic_params != 0 && len(type_entities) == 0 {
			do_newline(writer, flags)
			indent += 1
			do_indent(writer, flags)
			indent -= 1
			io.write_string(w, "<span class=\"comment\">… ")
			io.write_string(w, "// ")
			io.write_string(w, "See source for fields")
			io.write_string(w, "</span>")
			do_newline(writer, flags)
		} else {
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

		if type.polymorphic_params != 0 && len(type_entities) == 0 {
			do_newline(writer, flags)
			indent += 1
			do_indent(writer, flags)
			indent -= 1
			io.write_string(w, "<span class=\"comment\">… ")
			io.write_string(w, "// ")
			io.write_string(w, "See source for fields")
			io.write_string(w, "</span>")
			do_newline(writer, flags)
		} else {
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

		value, value_known := i128(-1), true

		for entity_index, i in type_entities {
			e := &cfg.entities[entity_index]
			docs, comment := str(e.docs), str(e.comment)

			write_lead_comment(writer, flags, docs, i)

			name := str(e.name)
			init_string := str(e.init_string)

			implicit := init_string == "" && value_known
			if init_string == "" {
				value += 1
			} else {
				value, value_known = parse_integer_literal(init_string)
			}

			do_indent(writer, flags)
			if implicit {
				// shown on hover by the stylesheet
				fmt.wprintf(w, `<span class="doc-enum-member" data-value="%d">`, value)
			}
			io.write_string(w, name)

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
			if implicit {
				io.write_string(w, "</span>")
			}

			do_newline(writer, flags)
		}
		indent -= 1
		do_indent(writer, flags)
		io.write_string(w, "}")
	case .Parameters:
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
			if .Force_Multiple_Lines in flags && len(type_entities) >= 2 {
				span_multiple_lines = true
			}
		}
		flags -= {.Force_Multiple_Lines}

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
		io.write_string(w, "<span class=\"directive\">#simd</span>")
		io.write_string(w, `[<span class="number">`)
		io.write_uint(w, uint(type.elem_counts[0]))
		io.write_string(w, `</span>]`)
		write_type(writer, cfg.types[type_types[0]], flags)
	case .SOA_Struct_Fixed:
		io.write_string(w, "<span class=\"directive\"><a href=\"https://odin-lang.org/docs/overview/#soa-data-types\">#soa</a></span>[")
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

write_doc_line :: proc(w: io.Writer, text: string, pkg: ^doc.Pkg = nil) {
	ctx := Doc_Context{pkg = pkg, owner = str(pkg.name) if pkg != nil else "directory"}
	write_markdown_inline(w, text, &ctx, "code-inline")
}

write_docs :: proc(w: io.Writer, docs: string, name: string = "", doc_ctx: ^Doc_Context = nil) {
	docs := docs

	default_ctx := Doc_Context{owner = name}
	ctx := doc_ctx if doc_ctx != nil else &default_ctx

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

	if strings.trim_space(docs) == "" {
		return
	}
	docs = strip_comment_gutter(docs)
	if strings.trim_space(docs) == "" {
		return
	}

	// Trim off space (not tabs) from the left.
	// Tabs actually have meaning.
	docs = strings.trim_left_proc(docs, proc(ch: rune) -> bool {
		if ch == '\t' { return false }
		return strings.is_space(ch)
	})
	docs = strings.trim_right_space(docs)

	Block_Kind :: enum {
		Paragraph,
		Code,
		Example,
		Operation,
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
	has_operation: bool

	is_list_item :: proc(text: string) -> bool {
		if strings.has_prefix(text, "- ") || strings.has_prefix(text, "* ") || strings.has_prefix(text, "+ ") {
			return true
		}
		i := 0
		for i < len(text) && '0' <= text[i] && text[i] <= '9' {
			i += 1
		}
		return i > 0 && i+1 < len(text) && (text[i] == '.' || text[i] == ')') && text[i+1] == ' '
	}
	// Tab-indented lines straight after a list item continue it, rather than starting a code block
	in_list := false

	// Find the minimum common prefix length of tabs, so an entire doc comment can be indented
	// without it rendering in a <pre> tag.
	if len(lines_to_process) > 0 {
		min_tabs: Maybe(int)
		for line in lines_to_process {
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
			for &line in lines_to_process {
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

		switch curr_block_kind {
		case .Paragraph:
			switch {
			case strings.has_prefix(line, "Example:"):
				next_block_kind = .Example
				has_example = true
			case strings.has_prefix(line, "Operation:"):
				next_block_kind = .Operation
				has_operation = true
			case strings.has_prefix(line, "Output:"):
				next_block_kind = .Output
				has_any_output = true
			case strings.has_prefix(line, "Possible Output:"):
				next_block_kind = .Possible_Output
				has_any_output = true
			case strings.has_prefix(line, "\t") && !in_list:
				next_block_kind = .Code
			case strings.has_prefix(line, "// Defined internally by the compiler"):
				next_block_kind = .Example
				has_example = true
			}
		case .Code:
			switch {
			case strings.has_prefix(line, "Example:"):
				next_block_kind = .Example
				has_example = true
			case strings.has_prefix(line, "Operation:"):
				next_block_kind = .Operation
				has_operation = true
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
			case strings.has_prefix(line, "Operation:"):
				next_block_kind = .Operation
				has_operation = true
			case strings.has_prefix(line, "Output:"):
				next_block_kind = .Output
				has_any_output = true
			case strings.has_prefix(line, "Possible Output:"):
				next_block_kind = .Possible_Output
				has_any_output = true
			case !strings.has_prefix(line, "\t") && text != "":
				next_block_kind = .Paragraph
			}
		case .Output, .Possible_Output, .Operation:
			switch {
			case strings.has_prefix(line, "Example:"):
				next_block_kind = .Example
				has_example = true
			case !strings.has_prefix(line, "\t") && text != "":
				next_block_kind = .Paragraph
			}
		}

		if curr_block_kind != next_block_kind {
			append(&blocks, Block{curr_block_kind, lines_to_process[start:i]})
			curr_block_kind = next_block_kind
			start = i
		}

		if next_block_kind == .Paragraph {
			in_list = is_list_item(text) || (in_list && strings.has_prefix(line, "\t") && text != "")
		} else {
			in_list = false
		}
	}

	if start < len(lines_to_process) {
		append(&blocks, Block{curr_block_kind, lines_to_process[start:]})
	}

	if has_any_output && !has_example {
		doc_warnf("The documentation for %q has an output block but no example", ctx.owner)
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
			write_markdown(w, block_lines, ctx)
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

		case .Operation:
			// Operation block starts with `Operation:` and a number of white spaces,
			operation_lines := trim_empty_and_subtitle_lines_and_replace_lt(block.lines, "Operation:")

			io.write_string(w, "<details open class=\"code-example\">\n")
			defer io.write_string(w, "</details>\n")
			io.write_string(w, "<summary><b>Operation:</b></summary>\n")
			io.write_string(w, `<pre><code class="hljs language-odin" data-lang="odin">`)
			for line in operation_lines {
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

write_sidebar_toggle :: proc(w: io.Writer, name, label: string) {
	fmt.wprintf(w, `<button type="button" class="odin-sidebar-toggle" data-sidebar="%s" onclick="toggleSidebar(this)" aria-expanded="true" title="Toggle %s">`, name, label)
	io.write_string(w, `<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M10 3 5 8l5 5"/></svg>`)
	fmt.wprintf(w, `<span>%s</span></button>`+"\n", label)
}

write_pkg_sidebar :: proc(w: io.Writer, curr_pkg: ^doc.Pkg, collection: ^Collection, pkg_name: string, path: string) {

	fmt.wprintln(w, `<nav id="pkg-sidebar" class="col-lg-2 odin-sidebar-border navbar-light sticky-top odin-below-navbar">`)
	defer fmt.wprintln(w, `</nav>`)

	write_sidebar_toggle(w, "pkg-sidebar", "Packages")

	fmt.wprintln(w, `<div class="odin-sidebar-content pb-3">`)
	defer fmt.wprintln(w, `</div>`)

	if pkg_name != "" {
		fmt.wprintf(w, `<div class="pkg-sidebar-current">Current Package: <em><a href="%s/%s">%s</a></em></div>` + "\n", collection.base_url, path, pkg_name)
	}

	fmt.wprintf(
		w,
		"<h4 class=\"pkg-sidebar-title\"><a style=\"text-transform: capitalize; color: inherit;\" href=\"%s\">%s Library</a></h4>\n",
		collection.base_url,
		collection.name,
	)

	fmt.wprintln(w, `<ul>`)
	defer fmt.wprintln(w, `</ul>`)

	write_side_bar_item :: proc(w: io.Writer, curr_pkg: ^doc.Pkg, collection: ^Collection, dir: ^Dir_Node, is_active: bool) {
		if len(dir.children) != 0 {
			fmt.wprint(w, `<li class="nav-item pkg-sidebar-group">`)
		} else {
			fmt.wprint(w, `<li class="nav-item">`)
		}
		defer fmt.wprintln(w, `</li>`)
		if dir.pkg == curr_pkg && (curr_pkg != nil || is_active) {
			fmt.wprintf(w, `<a class="active" href="%s/%s">%s</a>`, collection.base_url, dir.path, dir.name)
		} else if dir.pkg != nil || dir.name == "builtin" || dir.name == "intrinsics" {
			fmt.wprintf(w, `<a href="%s/%s">%s</a>`, collection.base_url, dir.path, dir.name)
		} else {
			fmt.wprintf(w, `<span class="pkg-sidebar-label">%s</span>`, dir.name)
		}
		if len(dir.children) != 0 {
			fmt.wprintln(w, "<ul>")
			defer fmt.wprintln(w, "</ul>\n")
			for child in dir.children {
				fmt.wprint(w, `<li>`)
				defer fmt.wprintln(w, `</li>`)
				if child.pkg == curr_pkg {
					fmt.wprintf(w, `<a class="active" href="%s/%s">`, collection.base_url, child.path)
				} else if child.pkg != nil {
					fmt.wprintf(w, `<a href="%s/%s">`, collection.base_url, child.path)
				} else {
					io.write_string(w, `<span class="pkg-sidebar-label">`)
				}
				write_breakable_name(w, child.name)
				if child.pkg == curr_pkg || child.pkg != nil {
					io.write_string(w, `</a>`)
				} else {
					io.write_string(w, `</span>`)
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
	procs:         [dynamic]doc.Scope_Entry,
	proc_groups:   [dynamic]doc.Scope_Entry,
	types:         [dynamic]doc.Scope_Entry,
	vars:          [dynamic]doc.Scope_Entry,
	consts:        [dynamic]doc.Scope_Entry,
	config_values: [dynamic]doc.Scope_Entry,

	all:         [dynamic]doc.Scope_Entry,

	ordering: [6]struct{name: string, entries: []doc.Scope_Entry, ignore: bool},
}

entity_key :: proc(entry: doc.Scope_Entry) -> string {
	return str(entry.name)
}

pkg_entries_gather :: proc(pkg: ^doc.Pkg) -> (entries: Pkg_Entries) {
	pkg_name := str(pkg.name)

	for entry in array(pkg.entries) {
		e := &cfg.entities[entry.entity]
		name := str(e.name)
		if name == "" || (name[0] == '_' && !strings.has_prefix(pkg_name, "simd")) {
			continue
		}
		name = str(entry.name)
		if name == "" || (name[0] == '_' && !strings.has_prefix(pkg_name, "simd")) {
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

		#partial switch e.kind {
		case .Constant, .Variable:
			if strings.has_prefix(str(e.init_string), "#config") {
				append(&entries.config_values, entry)
			}
		}
	}

	slice.sort_by_key(entries.procs[:],         entity_key)
	slice.sort_by_key(entries.proc_groups[:],   entity_key)
	slice.sort_by_key(entries.types[:],         entity_key)
	slice.sort_by_key(entries.vars[:],          entity_key)
	slice.sort_by_key(entries.consts[:],        entity_key)
	slice.sort_by_key(entries.config_values[:], entity_key)
	slice.sort_by_key(entries.all[:],           entity_key)

	entries.ordering = {
		{"Types",            entries.types[:], false},
		{"Constants",        entries.consts[:], false},
		{"Variables",        entries.vars[:], false},
		{"Procedures",       entries.procs[:], false},
		{"Procedure Groups", entries.proc_groups[:], false},
		{"`#config` values", entries.config_values[:], len(entries.config_values) == 0},
	}
	return
}

pkg_entries_destroy :: proc(entries: ^Pkg_Entries) {
	delete(entries.procs)
	delete(entries.proc_groups)
	delete(entries.types)
	delete(entries.vars)
	delete(entries.consts)
	delete(entries.config_values)
	entries^ = {}
}

write_search :: proc(w: io.Writer, kind: enum { Package, Collection, All}, hint := "") {
	class := ""
	switch kind {
	case .Package:    class = "odin-search-package"
	case .Collection: class = "odin-search-collection"
	case .All:        class = "odin-search-all"
	}
	fmt.wprintf(w, `
		<div class="odin-search-wrapper">
			<input type="search" id="odin-search" class="%s" autocomplete="off" spellcheck="false" placeholder="Fuzzy Search..." autofocus>
			<div class="odin-search-shortcut">
				<div class="odin-search-key key-macos">⌘K</div>
				<div class="odin-search-key key-windows">Ctrl+K</div>
				<span class="odin-search-or">or</span>
				<div class="odin-search-key">/</div>
			</div>
		</div>
	`, class)
	fmt.wprintln(w)
	if hint != "" {
		fmt.wprintf(w, `<p class="odin-search-hint">%s</p>`+"\n", hint)
	}

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

the_sort_proc :: proc(a, b: ^doc.Entity) -> (cmp: slice.Ordering) {
	cmp = slice.cmp(a.kind, b.kind)
	if cmp != .Equal { return }
	cmp = slice.cmp(str(a.name), str(b.name))
	return
}

MAX_PROCS_BEFORE_HIDING :: 24

print_procs :: proc(w:               io.Writer,
                    pkg:             ^doc.Pkg,
                    parent:          ^doc.Entity,
                    related_procs:   []^doc.Entity,
                    proc_names_seen: ^map[string]bool,
                    is_inherited:    bool,
                    title:           string,
                    ignore_procedure_group_suffix: bool = false) {
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
			if len(related_procs) < MAX_PROCS_BEFORE_HIDING {
				fmt.wprintln(w, "<details class=\"odin-doc-toggle\" open>")
			} else {
				fmt.wprintln(w, "<details class=\"odin-doc-toggle\">")
			}
			fmt.wprintln(w, `<summary class="hideme">`)
			if is_inherited {
				fmt.wprintf(
					w,
					"<h6 style=\"display:inline-block\">Procedures Through `using` From "+`<a href="%s/%s/#%s">%s</a></h5>`,
					collection.base_url,
					collection.pkg_to_path[pkg],
					parent_name,
					parent_name,
				)
				fmt.wprintln(w)
			} else {
				fmt.wprintf(w, "<h4 style=\"display:inline-block\">%s</h4>\n", title)
			}
			fmt.wprintln(w, "</summary>")
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

		if e.kind == .Proc_Group && !ignore_procedure_group_suffix {
			fmt.wprintf(w, `&nbsp;<em>(procedure groups)</em>`)
		}

		fmt.wprintf(w, "</li>")

		fmt.wprintln(w)
	}

	if seen_item {
		fmt.wprintln(w, "</ul>")
		fmt.wprintln(w, "</details>")
	}
}


// One-time reverse indices per package, replacing the per-entity full scans in
// write_related_* (previously ~O(types * procs); now O(entries)). A type-name
// entity is "related" to a proc/group by parameter or by result, via the same
// three matches the old check_proc used, so the rendered lists are unchanged:
//   *_by_type:   the (possibly dereferenced) parameter type is the entity's type
//   *_by_entity: a `.Named` parameter refers to the entity itself
//   *_by_name:   a generic-instantiation parameter's base name equals the name
Pkg_Relations :: struct {
	param_by_type:    map[doc.Type_Index][dynamic]^doc.Entity,
	param_by_entity:  map[^doc.Entity]   [dynamic]^doc.Entity,
	param_by_name:    map[string]        [dynamic]^doc.Entity,
	result_by_type:   map[doc.Type_Index][dynamic]^doc.Entity,
	result_by_entity: map[^doc.Entity]   [dynamic]^doc.Entity,
	result_by_name:   map[string]        [dynamic]^doc.Entity,
	groups_by_member: map[^doc.Entity]   [dynamic]^doc.Entity, // proc-groups containing a given procedure
	consts_by_type:   map[doc.Type_Index][dynamic]^doc.Entity, // constants of a given type
}

pkg_relations_get :: proc(pkg: ^doc.Pkg) -> ^Pkg_Relations {
	collect_relations :: proc(src, value: ^doc.Entity, results: bool,
	                          by_type:   ^map[doc.Type_Index][dynamic]^doc.Entity,
	                          by_entity: ^map[^doc.Entity][dynamic]^doc.Entity,
	                          by_name:   ^map[string][dynamic]^doc.Entity) {
		pt := base_type(cfg.types[src.type])
		if pt.kind != .Proc {
			return
		}
		tps := array(pt.types)
		if len(tps) <= int(results) {
			return
		}
		for param_idx in array(cfg.types[tps[int(results)]].entities) {
			raw_ti := cfg.entities[param_idx].type
			map_append(by_type, raw_ti, value) // identity match on the raw type

			t := &cfg.types[raw_ti]
			#partial switch t.kind {
			case .Named, .Generic:
				// no deref
			case .Pointer, .Multi_Pointer:
				inner := array(t.types)[0]
				map_append(by_type, inner, value) // identity match after deref
				t = &cfg.types[inner]
			case:
				continue
			}

			#partial switch t.kind {
			case .Named:
				ne := &cfg.entities[array(t.entities)[0]]
				map_append(by_entity, ne, value)
				if base, sep, _ := strings.partition(str(ne.name), "("); sep == "(" {
					map_append(by_name, base, value)
				}
			case .Generic:
				tt := array(t.types)
				if len(tt) == 1 {
					gt := cfg.types[tt[0]]
					if gt.kind == .Named {
						if base, sep, _ := strings.partition(str(gt.name), "("); sep == "(" {
							map_append(by_name, base, value)
						}
					}
				}
			}
		}
	}

	map_append :: proc(m: ^map[$K][dynamic]^doc.Entity, k: K, v: ^doc.Entity) {
		arr := m[k]
		append(&arr, v)
		m[k] = arr
	}

	@(static)
	pkg_relations_cache: map[^doc.Pkg]^Pkg_Relations

	if r, ok := pkg_relations_cache[pkg]; ok {
		return r
	}
	r := new(Pkg_Relations)

	for entry in array(pkg.entries) {
		e := &cfg.entities[entry.entity]
		if strings.has_prefix(str(e.name), "_") {
			continue // matches the old `_`-prefix skips in every write_related_*
		}
		#partial switch e.kind {
		case .Procedure:
			collect_relations(e, e, false, &r.param_by_type,  &r.param_by_entity,  &r.param_by_name)
			collect_relations(e, e, true,  &r.result_by_type, &r.result_by_entity, &r.result_by_name)
		case .Proc_Group:
			for midx in array(e.grouped_entities) {
				m := &cfg.entities[midx]
				collect_relations(m, e, false, &r.param_by_type,  &r.param_by_entity,  &r.param_by_name)
				collect_relations(m, e, true,  &r.result_by_type, &r.result_by_entity, &r.result_by_name)
				map_append(&r.groups_by_member, m, e)
			}
		case .Constant:
			map_append(&r.consts_by_type, e.type, e)
		}
	}

	pkg_relations_cache[pkg] = r
	return r
}

relation_list :: proc(m: map[$K][dynamic]^doc.Entity, k: K) -> []^doc.Entity {
	if arr, ok := m[k]; ok {
		return arr[:]
	}
	return nil
}

relation_collect :: proc(rel: ^Pkg_Relations, parent: ^doc.Entity, results: bool) -> (out: [dynamic]^doc.Entity) {
	by_type, by_entity, by_name: []^doc.Entity
	if results {
		by_type   = relation_list(rel.result_by_type,   parent.type)
		by_entity = relation_list(rel.result_by_entity, parent)
		by_name   = relation_list(rel.result_by_name,   str(parent.name))
	} else {
		by_type   = relation_list(rel.param_by_type,   parent.type)
		by_entity = relation_list(rel.param_by_entity, parent)
		by_name   = relation_list(rel.param_by_name,   str(parent.name))
	}
	ppkg := cfg.entity_to_pkg[parent]

	seen: map[^doc.Entity]bool
	defer delete(seen)
	for e in by_type {
		if cfg.entity_to_pkg[e] != ppkg { continue }
		if e in seen { continue }
		seen[e] = true
		append(&out, e)
	}
	for e in by_entity {
		if e in seen { continue }
		seen[e] = true
		append(&out, e)
	}
	for e in by_name {
		if e in seen { continue }
		seen[e] = true
		append(&out, e)
	}
	slice.sort_by_cmp(out[:], the_sort_proc)
	return
}

write_related_procedures :: proc(w: io.Writer, pkg: ^doc.Pkg, parent: ^doc.Entity, proc_names_seen: ^map[string]bool, is_inherited := false) {
	rel := pkg_relations_get(pkg)

	params := relation_collect(rel, parent, false)
	defer delete(params)
	print_procs(w, pkg, parent, params[:], proc_names_seen, is_inherited, title="Related Procedures With Parameters")

	results: [dynamic]^doc.Entity
	defer delete(results)
	if !is_inherited {
		results = relation_collect(rel, parent, true)
	}
	print_procs(w, pkg, parent, results[:], proc_names_seen, is_inherited, title="Related Procedures With Returns")

	// Recursive `using` inheritance (unchanged).
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

write_related_procedure_groups :: proc(w: io.Writer, pkg: ^doc.Pkg, parent: ^doc.Entity, proc_names_seen: ^map[string]bool, is_inherited := false) {
	rel := pkg_relations_get(pkg)

	groups: [dynamic]^doc.Entity
	defer delete(groups)
	seen: map[^doc.Entity]bool
	defer delete(seen)
	for g in relation_list(rel.groups_by_member, parent) {
		if g in seen { continue }
		seen[g] = true
		append(&groups, g)
	}
	slice.sort_by_cmp(groups[:], the_sort_proc)

	print_procs(w, pkg, parent, groups[:], proc_names_seen, is_inherited, title="Related Procedure Groups", ignore_procedure_group_suffix=true)
}

write_related_constants :: proc(w: io.Writer, pkg: ^doc.Pkg, parent: ^doc.Entity) {
	#partial switch pt := cfg.types[parent.type]; pt.kind {
	case .Invalid, .Basic, .Generic:
		return
	}

	rel := pkg_relations_get(pkg)
	related := relation_list(rel.consts_by_type, parent.type)
	if len(related) == 0 {
		return
	}

	list := make([dynamic]^doc.Entity, 0, len(related))
	defer delete(list)
	append(&list, ..related)
	slice.sort_by_cmp(list[:], the_sort_proc)

	constants_seen := make(map[string]bool)
	defer delete(constants_seen)

	collection := cfg.pkg_to_collection[pkg]
	fmt.wprintfln(w, "<h4>Related Constants</h4>")
	fmt.wprintln(w, "<ul>")
	for e in list {
		name := str(e.name)
		if constants_seen[name] { continue }
		constants_seen[name] = true
		fmt.wprintf(w, "<li>")
		fmt.wprintf(w, `<a href="%s/%s/#%s">%s</a>`, collection.base_url, collection.pkg_to_path[pkg], name, name)
		fmt.wprintfln(w, "</li>")
	}
	fmt.wprintln(w, "</ul>")
}

slugify :: proc(s: string, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	prev_dash := true // suppress leading separators
	for r in s {
		switch {
		case r >= 'A' && r <= 'Z':
			strings.write_rune(&b, r + 32)
			prev_dash = false
		case (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9'):
			strings.write_rune(&b, r)
			prev_dash = false
		case:
			if !prev_dash {
				strings.write_byte(&b, '-')
				prev_dash = true
			}
		}
	}
	return strings.trim_right(strings.to_string(b), "-")
}


write_entry :: proc(w: io.Writer, pkg: ^doc.Pkg, entry: doc.Scope_Entry) {
	write_declaration_attributes :: proc(w: io.Writer, e: ^doc.Entity) {
		skip :: proc(name: string) -> bool {
			switch name {
			case "objc_name", "objc_type", "objc_is_class_method", "objc_class":
				return true
			case "private":
				return true
			}
			return false
		}

		for attr in array(e.attributes) {
			name := str(attr.name)
			if skip(name) {
				continue
			}
			io.write_string(w, `<span class="odin-attribute">`)
			io.write_string(w, "@(")
			io.write_string(w, escape_html_string(name))
			if value := str(attr.value); value != "" {
				io.write_byte(w, '=')
				io.write_string(w, escape_html_string(value))
			}
			io.write_string(w, ")")
			io.write_string(w, "</span>")
			io.write_string(w, "\n")
		}
	}

	write_entity_reference :: proc(w: io.Writer, pkg: ^doc.Pkg, entity: ^doc.Entity, entry_name: string) {
		name := str(entity.name)

		this_pkg := &cfg.pkgs[cfg.files[entity.pos.file].pkg]
		if .Builtin_Pkg_Builtin in entity.flags {
			fmt.wprintf(w, `<a href="/base/builtin">builtin</a>.<a href="/base/builtin#{0:s}">{0:s}</a>`, name)
			return
		} else if .Builtin_Pkg_Intrinsics in entity.flags {
			fmt.wprintf(w, `<a href="/base/intrinsics">intrinsics</a>.<a href="/base/intrinsics#{0:s}">{0:s}</a>`, name)
			for iname in intrinsics_table {
				if iname.name == name && iname.type != "" {
					fmt.wprintf(w, `<br>%s :: %s`, entry_name, add_styling_to_builtin(iname.type))
					if iname.kind == "b" {
						io.write_string(w, " {…}")
					}
					break
				}
			}
			return
		} else if pkg != this_pkg {
			fmt.wprintf(w, "%s.", pkg_import_name(this_pkg))
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

	// An Objective-C class links to Apple's documentation
	is_declared_here := name == entity_name && entity_pkg == pkg
	class: ^Objc_Class
	if is_declared_here && e.kind == .Type_Name {
		class = objc_class_of(pkg, e)
	}

	path := collection.pkg_to_path[pkg]
	filename := slashpath.base(str(cfg.files[e.pos.file].name))
	fmt.wprintf(w, "<h3 id=\"{0:s}\"><span><a class=\"doc-id-link\" href=\"#{0:s}\">{0:s}", name)
	fmt.wprintf(w, "<span class=\"a-hidden\">&nbsp;¶</span></a>")
	if is_declared_here {
		write_objc_badges(w, objc_badges(pkg, e))
	}
	fmt.wprintf(w, "</span>")
	if e.pos.file != 0 && e.pos.line > 0 {
		src_url := fmt.tprintf("%s/%s/%s#L%d", collection.source_url, path, filename, e.pos.line)
		io.write_string(w, `<div class="doc-source">`)
		if c_name := entity_c_name(e, name); c_name != "" && is_declared_here {
			fmt.wprintf(w, "<span class=\"doc-c-name\" title=\"The C symbol this binds\"><em>C</em><span class=\"doc-source-loc\"> &middot; %s</span></span>", c_name)
		}
		if class != nil {
			if url := objc_doc_url(pkg, class.name); url != "" {
				fmt.wprintf(w, "<a href=\"{0:s}\" title=\"Apple's documentation for {1:s}\"><em>Apple Docs</em><span class=\"doc-source-loc\"> &middot; {1:s}</span></a>", url, class.name)
			}
		}
		fmt.wprintf(w, "<a href=\"{0:s}\"><em>Source</em><span class=\"doc-source-loc\"> &middot; {1:s}:{2:d}</span></a></div>", src_url, filename, e.pos.line)
	}
	fmt.wprintf(w, "</h3>\n")
	fmt.wprintln(w, `<div>`)

	doc_ctx := Doc_Context{pkg = pkg, owner = fmt.tprintf("%s.%s", str(pkg.name), name), heading_prefix = name, entity = e, self_name = name}

	if raw, ok := find_entity_attribute(e, "deprecated"); ok {
		msg, _, unq_ok := strconv.unquote_string(raw, context.temp_allocator)
		if !unq_ok {
			msg = raw
		}
		io.write_string(w, `<div class="doc-deprecated" role="note"><strong>Deprecated.</strong>`)
		if strings.trim_space(msg) != "" {
			io.write_byte(w, ' ')
			write_markdown_inline(w, msg, &doc_ctx)
		}
		io.write_string(w, "</div>\n")
	}

	// Important: Don't trim `the_docs`.
	// See comment block below where we optionally replace it with `e.comment`.
	the_docs := str(e.docs)

	if name != entity_name || entity_pkg != pkg {
		reference := strings.builder_make(context.temp_allocator)
		fmt.sbprintf(&reference, "%s :: ", name)
		write_entity_reference(strings.to_writer(&reference), pkg, e, name)
		fmt.wprintf(w, `<pre class="doc-code">%s</pre>`+"\n", strings.to_string(reference))
		if e.kind == .Type_Name {
			add_type_preview(name, strings.to_string(reference))
		}

		// If `e` doesn't have a comment and it's a reference to a built-in or intrinsic with a comment, copy its comment.
		// Saves work and prevents those comments going out of sync.
		if the_docs == "" {
			if .Builtin_Pkg_Builtin in e.flags {
				for bname in builtins {
					if bname.name == entity_name && bname.type != "" {
						the_docs = bname.comment
						break
					}
				}
			} else if .Builtin_Pkg_Intrinsics in e.flags {
				for iname in intrinsics_table {
					if iname.name == entity_name && iname.type != "" {
						the_docs = iname.comment
						break
					}
				}
			}
		}
	} else {
		switch e.kind {
		case .Invalid, .Import_Name, .Library_Name:
			// ignore
		case .Constant:
			fmt.wprint(w, `<pre class="doc-code">`)
			write_declaration_attributes(w, e)
			the_type := cfg.types[e.type]

			init_string := escape_html_string(str(e.init_string))
			if init_string == "" {
				doc_warnf("%s: constant has no value", doc_ctx.owner)
				init_string = "…"
			}

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
					if strings.has_prefix(init_string, "runtime.") {
						io.write_string(w, add_styling_to_builtin(init_string))
					} else {
						io.write_string(w, init_string)
					}
				}
			} else {
				io.write_string(w, init_string)
			}
			fmt.wprintln(w, "</pre>")
			write_config_flag(w, str(e.init_string))
		case .Variable:
			fmt.wprint(w, `<pre class="doc-code">`)
			write_declaration_attributes(w, e)
			fmt.wprintf(w, "%s: ", name)
			write_type(writer, cfg.types[e.type], {.Allow_Indent})
			init_string := str(e.init_string)
			if init_string != "" {
				io.write_string(w, " = ")
				io.write_string(w, "…")
			}
			fmt.wprintln(w, "</pre>")

		case .Type_Name:
			definition := strings.builder_make(context.temp_allocator)
			dw := strings.to_writer(&definition)
			writer.w = dw
			write_declaration_attributes(dw, e)
			fmt.wprintf(dw, "%s :: ", name)
			the_type := cfg.types[e.type]
			type_to_print := the_type
			if base_type(type_to_print).kind == .Basic && str(pkg.name) == "c" {
				io.write_string(dw, str(e.init_string))
			} else {
				if the_type.kind == .Named && .Type_Alias not_in e.flags {
					if e.pos == cfg.entities[array(the_type.entities)[0]].pos {
						bt := base_type(the_type)
						#partial switch bt.kind {
						case .Struct, .Union, .Proc, .Enum:
							// Okay
						case:
							io.write_string(dw, `<span class="keyword-type">distinct</span> `)
						}
						type_to_print = bt
					}
				}
				write_type(writer, type_to_print, {.Allow_Indent})
			}
			writer.w = w
			write_definition(w, strings.to_string(definition))
			if class != nil {
				// hovering a class shows what it is rather than `struct { using _: Parent }`
				preview := strings.builder_make(context.temp_allocator)
				write_objc_class_preview(strings.to_writer(&preview), pkg, class, strings.to_string(definition))
				add_type_preview(name, strings.to_string(preview))
				fmt.wprintf(w, `<template class="doc-type-preview">%s</template>`+"\n", strings.to_string(preview))
			} else {
				add_type_preview(name, strings.to_string(definition))
			}
		case .Builtin:
			fmt.wprint(w, `<pre class="doc-code">`)
			fmt.wprintf(w, "%s :: ", name)
			write_entity_reference(w, pkg, e, name)
			fmt.wprint(w, `</pre>`)
		case .Procedure:
			fmt.wprint(w, `<pre class="doc-code">`)
			write_declaration_attributes(w, e)
			fmt.wprintf(w, "%s :: ", name)

			// NOTE(bill): A signature too long for one line gets a parameter per line as those with many parameters do
			signature := strings.builder_make(context.temp_allocator)
			writer.w = strings.to_writer(&signature)
			write_type(writer, cfg.types[e.type], {.Allow_Multiple_Lines})
			one_line := strings.to_string(signature)
			if !strings.contains_rune(one_line, '\n') && len(name)+len(" :: ")+visible_width(one_line)+len(" {…}") > MAX_SIGNATURE_WIDTH {
				strings.builder_reset(&signature)
				clear(&writer.generic_scope) // filled by the first attempt, and it decides how `$T` is written
				write_type(writer, cfg.types[e.type], {.Allow_Multiple_Lines, .Force_Multiple_Lines})
			}
			writer.w = w
			io.write_string(w, strings.to_string(signature))

			write_where_clauses(w, array(e.where_clauses))
			if .Foreign in e.flags {
				fmt.wprint(w, " ---")
			} else {
				fmt.wprint(w, " {…}")
			}
			fmt.wprintln(w, "</pre>")

			write_objc_call(w, pkg, e)

		case .Proc_Group:
			fmt.wprint(w, `<pre class="doc-code">`)
			write_declaration_attributes(w, e)
			fmt.wprintf(w, "%s :: <span class=\"keyword-type\">proc</span>{{\n", name)
			for entity_index in array(e.grouped_entities) {
				this_proc := &cfg.entities[entity_index]
				io.write_byte(w, '\t')
				write_entity_reference(w, pkg, this_proc, name)
				io.write_byte(w, ',')
				io.write_byte(w, '\n')
			}
			fmt.wprintln(w, "}")
			fmt.wprintln(w, "</pre>")

			write_objc_call(w, pkg, e)
		}
	}
	fmt.wprintln(w, `</div>`)

	// NOTE(Jeroen):
	//
	// If we trim `the_docs` before passing it to `write_docs`, all but the first line
	// turn into `<pre>`, and `[[ title ; link ]]` tags are no longer resolved either.
	// Laytan discovered this on the docs for `readlink` in `core:sys/posix`.
	// Instead check if `the_docs` would be empty if trimmed in order to substitute it with
	// the comments, but don't actually mess with the input. It seems to upset CommonMark,
	// and `write_docs` does its own trimming as it is.
	if strings.trim_space(the_docs) == "" {
		the_docs = str(e.comment)
	}

	if the_docs != "" {
		fmt.wprintln(w, `<details class="odin-doc-toggle" open>`)
		fmt.wprintln(w, `<summary class="hideme"><span>&nbsp;</span></summary>`)
		write_docs(w, the_docs, doc_ctx = &doc_ctx)
		fmt.wprintln(w, `</details>`)
	}


	if _, ok := find_entity_attribute(e, "objc_class"); ok {
		fmt.wprintln(w, `<div>`)
		defer fmt.wprintln(w, `</div>`)

		method_names_seen: map[string]bool
		write_objc_methods(w, pkg, entity_pkg, e, &method_names_seen)
		delete(method_names_seen)
	} else if e.kind == .Type_Name {
		proc_names_seen: map[string]bool
		write_related_procedures(w, pkg, e, &proc_names_seen)
		write_related_constants(w, pkg, e)
		delete(proc_names_seen)
	}
	if e.kind == .Procedure {
		proc_names_seen: map[string]bool
		write_related_procedure_groups(w, pkg, e, &proc_names_seen)
		delete(proc_names_seen)
	}
}

// Definitions longer than this show only their first lines until expanded
LONG_DEFINITION_LINES :: 50

write_definition :: proc(w: io.Writer, html: string) {
	lines := strings.count(html, "\n") + 1
	if lines <= LONG_DEFINITION_LINES {
		fmt.wprintf(w, `<pre class="doc-code">%s</pre>`+"\n", html)
		return
	}
	fmt.wprintf(w, `<pre class="doc-code doc-code-long">%s</pre>`+"\n", html)
	fmt.wprintf(w, `<button type="button" class="doc-code-expand" aria-expanded="false">Show all %d lines</button>`+"\n", lines)
}

// A package's type definitions, written to the "types.json" beside its page,
// from which hovering a type in a signature shows its definition
Type_Preview :: struct {
	name, html: string,
}
type_previews: [dynamic]Type_Preview

add_type_preview :: proc(name, html: string) {
	append(&type_previews, Type_Preview{strings.clone(name), strings.clone(html)})
}

write_json_string :: proc(w: io.Writer, s: string) {
	io.write_byte(w, '"')
	for r in s {
		switch r {
		case '"':  io.write_string(w, `\"`)
		case '\\': io.write_string(w, `\\`)
		case '\n': io.write_string(w, `\n`)
		case '\t': io.write_string(w, `\t`)
		case '\r': io.write_string(w, `\r`)
		case:
			if r < 0x20 {
				fmt.wprintf(w, `\u%04x`, r)
			} else {
				io.write_rune(w, r)
			}
		}
	}
	io.write_byte(w, '"')
}

write_type_previews :: proc(w: io.Writer) {
	io.write_string(w, "{\n")
	for p, i in type_previews {
		if i > 0 {
			io.write_string(w, ",\n")
		}
		write_json_string(w, p.name)
		io.write_string(w, ": ")
		write_json_string(w, p.html)
	}
	io.write_string(w, "\n}\n")

	for p in type_previews {
		delete(p.name)
		delete(p.html)
	}
	clear(&type_previews)
}

INDEX_MIN_GROUP_SIZE :: 3
INDEX_MIN_ENTRIES_TO_GROUP :: 16

index_group_prefix :: proc(name: string) -> string {
	if i := strings.index_byte(name, '_'); i > 0 {
		return name[:i]
	}
	return ""
}

scope_entry_name :: proc(e: doc.Scope_Entry) -> string {
	return str(e.name)
}

write_index_item :: proc(w: io.Writer, entry: doc.Scope_Entry) {
	name := str(entry.name)
	fmt.wprintf(w, "<li><a href=\"#{0:s}\">", name)
	write_breakable_name(w, name)
	io.write_string(w, "</a></li>\n")
}

write_breakable_name :: proc(w: io.Writer, name: string) {
	for i in 0..<len(name) {
		io.write_byte(w, name[i])
		if (name[i] == '_' || name[i] == '/') && i > 0 && i+1 < len(name) {
			io.write_string(w, "<wbr>")
		}
	}
}


walk_index_groups :: proc(
	w:           io.Writer,
	entries:     []$T,
	name_of:     proc(e: T) -> string,
	item:        proc(w: io.Writer, e: T),
	group_start: proc(w: io.Writer, prefix: string, count: int),
	group_end:   proc(w: io.Writer),
) {
	for i := 0; i < len(entries); /**/ {
		prefix := index_group_prefix(name_of(entries[i]))
		j := i + 1
		if prefix != "" {
			for j < len(entries) && index_group_prefix(name_of(entries[j])) == prefix {
				j += 1
			}
		}
		run := entries[i:j]
		if prefix != "" && len(run) >= INDEX_MIN_GROUP_SIZE {
			group_start(w, prefix, len(run))
			for e in run {
				item(w, e)
			}
			group_end(w)
		} else {
			for e in run {
				item(w, e)
			}
		}
		i = j
	}
}

index_group_start :: proc(w: io.Writer, prefix: string, count: int) {
	fmt.wprintf(w, `<li class="doc-index-group"><details open><summary>%s_… <span class="doc-index-group-count">(%d)</span></summary>`+"\n", prefix, count)
	fmt.wprintln(w, "<ul>")
}
index_group_end :: proc(w: io.Writer) {
	fmt.wprintln(w, "</ul></details></li>")
}

toc_group_start :: proc(w: io.Writer, prefix: string, count: int) {
	fmt.wprintf(w, `<li class="toc-group"><span class="toc-group-label">%s_…</span>`+"\n", prefix)
	fmt.wprintln(w, "<ul>")
}
toc_group_end :: proc(w: io.Writer) {
	fmt.wprintln(w, "</ul></li>")
}

write_index_body :: proc(w: io.Writer, entries: []doc.Scope_Entry) {
	if len(entries) < INDEX_MIN_ENTRIES_TO_GROUP {
		fmt.wprintln(w, "<ul>")
		for e in entries {
			write_toc_item(w, e)
		}
		fmt.wprintln(w, "</ul>")
		return
	}
	fmt.wprintln(w, `<ul class="doc-index-list">`)
	walk_index_groups(w, entries,
		name_of     = scope_entry_name,
		group_start = index_group_start,
		group_end   = index_group_end,
		item        = write_toc_item,
	)
	fmt.wprintln(w, "</ul>")
}

write_toc_item :: proc(w: io.Writer, entry: doc.Scope_Entry) {
	name := str(entry.name)
	if _, ok := find_entity_attribute(&cfg.entities[entry.entity], "deprecated"); ok {
		fmt.wprintf(w, `<li><a class="deprecated" href="#{0:s}" title="Deprecated"><s>{0:s}</s></a></li>`+"\n", name)
	} else {
		fmt.wprintf(w, "<li><a href=\"#{0:s}\">{0:s}</a></li>\n", name)
	}
}


write_toc_section :: proc(w: io.Writer, entries: []doc.Scope_Entry, item: proc(w: io.Writer, entry: doc.Scope_Entry) = write_index_item) {
	if len(entries) < INDEX_MIN_ENTRIES_TO_GROUP {
		for e in entries {
			item(w, e)
		}
		return
	}
	walk_index_groups(w, entries,
		name_of     = scope_entry_name,
		group_start = toc_group_start,
		group_end   = toc_group_end,
		item        = item,
	)
}

write_pkg :: proc(w: io.Writer, dir, path: string, pkg: ^doc.Pkg, collection: ^Collection, pkg_entries: Pkg_Entries) {
	fmt.wprintln(w, `<div class="row odin-main odin-docs-layout my-4" id="pkg">`)
	defer fmt.wprintln(w, `</div>`)

	write_pkg_sidebar(w, pkg, collection, str(pkg.name), path)

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

	files, any_hidden_files := pkg_listed_files(pkg)
	write_pkg_meta(w, collection, path, pkg, !collection_root_is_package, pkg_src_url, len(files), len(pkg_entries.all))

	if specific_target, ok := target_from_pkg(pkg); ok {
		fmt.wprintf(w, "<h4><strong>Warning:&nbsp;</strong>This was generated for <code>-target:%s</code> and might not represent every target this package supports.</h4>", specific_target)
	}

	// When this is the case, the collection page does not exists, so show license here.
	if collection_root_is_package {
		write_license(w, collection)
	}

	write_search(w, .Package)

	fmt.wprintln(w, `<div id="pkg-top">`)

	overview_docs := str(pkg.docs)
	overview_headings: [dynamic]Doc_Heading
	if strings.trim_space(overview_docs) != "" {
		fmt.wprintln(w, "<h2>Overview</h2>")
		fmt.wprintln(w, "<div id=\"pkg-overview\">")
		defer fmt.wprintln(w, "</div>")

		ctx := Doc_Context{pkg = pkg, owner = path, heading_prefix = "overview", headings = &overview_headings}
		write_docs(w, overview_docs, doc_ctx = &ctx)
	}

	// e.g. `core:image/png` on `core:image`'s page, which otherwise only the sidebar shows
	subpackages := make([dynamic]string, context.temp_allocator)
	if !collection_root_is_package {
		for sub_path, sub_pkg in collection.pkgs {
			if strings.has_prefix(sub_path, path) && strings.has_prefix(sub_path[len(path):], "/") && str(sub_pkg.name) != "os2" {
				append(&subpackages, sub_path)
			}
		}
		slice.sort(subpackages[:])
	}
	if len(subpackages) > 0 {
		fmt.wprintf(w, `<h2 id="pkg-packages">Packages <span class="pkg-count">%d</span></h2>`+"\n", len(subpackages))
		fmt.wprintln(w, `<table class="odin-pkg-table odin-subpkg-table">`)
		for sub_path in subpackages {
			sub_pkg := collection.pkgs[sub_path]
			if cfg.pkg_to_header[sub_pkg] != cfg.header {
				init_cfg_from_pkg(sub_pkg)
			}
			fmt.wprintf(w, `<tbody><tr><td class="pkg-name"><a href="%s/%s/">%s</a></td><td class="pkg-desc">`, collection.base_url, sub_path, sub_path[len(path)+1:])
			if line_doc, ok := pkg_line_doc(sub_pkg); ok {
				write_doc_line(w, line_doc, sub_pkg)
			}
			io.write_string(w, `</td><td class="pkg-import">`)
			write_copy_import_button(w, collection, sub_path, sub_pkg, "import")
			io.write_string(w, "</td></tr></tbody>\n")
		}
		fmt.wprintln(w, `</table>`)
		if cfg.pkg_to_header[pkg] != cfg.header {
			init_cfg_from_pkg(pkg)
		}
	}

	// Packages may only hold documentation
	has_entries := len(pkg_entries.all) > 0

	if has_entries {
		fmt.wprintln(w, `<div id="pkg-index">`)
		fmt.wprintln(w, `<h2>Index</h2>`)
	}


	write_index :: proc(w: io.Writer, name: string, entries: []doc.Scope_Entry) {
		fmt.wprintln(w, `<div>`)
		defer fmt.wprintln(w, `</div>`)


		slug := slugify(name, context.temp_allocator)
		fmt.wprintf(w, `<details class="doc-index" id="doc-index-{0:s}" aria-labelledby="doc-index-{0:s}-header">`+"\n", slug)
		fmt.wprintf(w, `<summary id="doc-index-{0:s}-header">`+"\n", slug)
		io.write_string(w, name)
		io.write_string(w, " (")
		io.write_int(w, len(entries))
		io.write_string(w, ")")
		fmt.wprintln(w, `</summary>`)
		defer fmt.wprintln(w, `</details>`)

		if len(entries) == 0 {
			io.write_string(w, "<p class=\"pkg-empty-section\">This section is empty.</p>\n")
		} else {
			write_index_body(w, entries)
		}
	}

	if has_entries {
		for eo in pkg_entries.ordering {
			if eo.ignore {
				continue
			}
			write_index(w, eo.name, eo.entries)
		}
		fmt.wprintln(w, "</div>")
	}
	fmt.wprintln(w, "</div>")


	write_entries :: proc(w: io.Writer, pkg: ^doc.Pkg, title: string, entries: []doc.Scope_Entry) {
		slug := slugify(title, context.temp_allocator)
		fmt.wprintf(w, "<h2 id=\"pkg-{0:s}\" class=\"pkg-header\">{1:s}</h2>\n", slug, title)
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

	if has_entries {
		fmt.wprintln(w, `<section class="documentation">`)
		for eo in pkg_entries.ordering {
			if eo.ignore {
				continue
			}
			write_entries(w, pkg, eo.name, eo.entries)
		}
		fmt.wprintln(w, "</section>")
	}

	fmt.wprintln(w, `<h2 id="pkg-source-files">Source Files</h2>`)
	fmt.wprintln(w, "<ul>")
	for filename in files {
		fmt.wprintf(w, `<li><a href="%s/%s/%s">%s</a></li>`, collection.source_url, path, filename, filename)
		fmt.wprintln(w)
	}
	if any_hidden_files {
		fmt.wprintln(w, "<li><em>(hidden platform specific files)</em></li>")
	}
	fmt.wprintln(w, "</ul>")

	{
		fmt.wprintln(w, `<h2 id="pkg-generation-information">Generation Information</h2>`)
		now := build_time()
		fmt.wprintf(w, "<p>Generated with <code>odin version %s (vendor %q) %s_%s @ %v</code></p>\n", ODIN_VERSION, ODIN_VENDOR, ODIN_OS, ODIN_ARCH, now)
	}



	fmt.wprintln(w, `</article>`)
	{
		write_link :: proc(w: io.Writer, id, text: string) {
			fmt.wprintf(w, `<li><a href="#%s">%s</a></li>`, id, text)
		}

		fmt.wprintln(w, `<div class="col-lg-2 odin-toc-border navbar-light"><div class="sticky-top odin-below-navbar py-3">`)
		write_sidebar_toggle(w, "toc-sidebar", "Contents")
		fmt.wprintln(w, `<nav id="TableOfContents">`)
		fmt.wprintln(w, `<ul>`)
		if overview_docs != "" {
			io.write_string(w, `<li><a href="#pkg-overview">Overview</a>`)
			if len(overview_headings) > 0 {
				top, next := max(int), max(int)
				for h in overview_headings {
					top = min(top, h.level)
				}
				count := 0
				for h in overview_headings {
					count += int(h.level == top)
					if h.level > top {
						next = min(next, h.level)
					}
				}
				// A lone title is skipped for the sections below it
				if count == 1 && next != max(int) {
					top = next
				}
				fmt.wprintln(w, `<ul>`)
				for h in overview_headings do if h.level == top {
					text, _ := strings.replace_all(h.text, "&", "&amp;", context.temp_allocator)
					fmt.wprintf(w, `<li><a href="#%s">%s</a></li>`+"\n", h.id, escape_html_string(text, context.temp_allocator))
				}
				io.write_string(w, `</ul>`)
			}
			fmt.wprintln(w, `</li>`)
		}
		if len(subpackages) > 0 {
			fmt.wprintf(w, `<li><a href="#pkg-packages">Packages<span class="toc-count">%d</span></a></li>`+"\n", len(subpackages))
		}
		// Objective-C methods are listed under their classes rather than with the other procedures
		toc_pkg = pkg
		class_names: map[string]bool
		defer delete(class_names)
		for entry in pkg_entries.types {
			e := &cfg.entities[entry.entity]
			if class := objc_class_of(pkg, e); class != nil && len(class.methods) > 0 && str(entry.name) == str(e.name) {
				class_names[str(e.name)] = true
			}
		}

		for eo in pkg_entries.ordering do if has_entries && !eo.ignore {
			slug := slugify(eo.name, context.temp_allocator)
			if len(eo.entries) == 0 {
				// listed like the Index lists it, and odin-lang.org's script.js needs a link for each heading
				fmt.wprintf(w, `<li class="toc-empty"><a href="#pkg-{0:s}">{1:s}<span class="toc-count">0</span></a></li>`+"\n", slug, eo.name)
				continue
			}

			entries := eo.entries
			item := write_index_item
			if len(class_names) > 0 {
				if eo.name == "Types" {
					item = write_toc_type_item
				} else {
					listed := make([dynamic]doc.Scope_Entry, context.temp_allocator)
					for entry in entries {
						if !objc_listed_under_class(pkg, entry, class_names) {
							append(&listed, entry)
						}
					}
					entries = listed[:]
				}
			}

			fmt.wprintf(w, `<li><a href="#pkg-{0:s}">{1:s}`, slug, eo.name)
			if len(entries) > 0 {
				fmt.wprintf(w, `<span class="toc-count">%d</span>`, len(entries))
			}
			io.write_string(w, `</a>`)
			fmt.wprintln(w, `<ul>`)
			write_toc_section(w, entries, item)
			fmt.wprintln(w, "</ul>")
			fmt.wprintln(w, "</li>")
		}
		write_link(w, "pkg-source-files", "Source Files")
		write_link(w, "pkg-generation-information", "Generation Information")
		fmt.wprintln(w, `</ul>`)
		fmt.wprintln(w, `</nav>`)
		fmt.wprintln(w, `</div></div>`)
	}

	fmt.wprintf(w, `<script type="text/javascript">var odin_pkg_name = "%s";</script>`+"\n", str(pkg.name))

}
