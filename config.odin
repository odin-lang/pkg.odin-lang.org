package odin_html_docs

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"
import "core:slice"
import "core:strings"

import doc "core:odin/doc-format"

Config :: struct {
	hide_core:    bool,
	_collections: map[string]Collection `json:"collections"`,

	// -- Start non configurable --
	header:   ^doc.Header,
	files:    []doc.File,
	pkgs:     []doc.Pkg,
	entities: []doc.Entity,
	types:    []doc.Type,

	// Maps are unordered, we want an order to places where it matters, like the homepage.
	// Why is 'collections' not a slice? Because the JSON package overwrites the full slice when
	// you unmarshal into it, with a map, when unmarshalling into it, the entries are added to existing ones.
	collections: [dynamic]^Collection,

	pkg_to_collection:  map[^doc.Pkg]^Collection,
}

Collection :: struct {
	name:            string,
	source_url:      string,
	base_url:        string,
	root_path:       string,
	license:         Collection_License,
	home:            Collection_Home,
	// Hides the collection from navigation but can still be
	// linked to.
	hidden:          bool,

	// -- Start non configurable --
	root:            ^Dir_Node,
	pkgs:            map[string]^doc.Pkg,
	pkg_to_path:     map[^doc.Pkg]string,
	pkg_entries_map: map[^doc.Pkg]Pkg_Entries,
}

Collection_License :: struct {
	text: string,
	url:  string,
}

Collection_Home :: struct {
	title:        Maybe(string),
	description:  Maybe(string),
	embed_readme: Maybe(string),
}

Collection_Error :: string

collection_validate :: proc(c: ^Collection) -> Maybe(Collection_Error) {
	c.name = strings.trim_space(c.name)
	c.source_url = strings.trim_space(c.source_url)
	c.base_url = strings.trim_space(c.base_url)
	c.license.text = strings.trim_space(c.license.text)
	c.license.url = strings.trim_space(c.license.url)
	c.root_path = strings.trim_space(c.root_path)

	if c.name == "" {
		return "collection requires the key \"name\" to be set to the name of the collection, example: \"core\"" \
	}
	if c.source_url == "" {
		return "collection requires the key \"source_url\" to be set to a URL that points to the root of collection on a website like GitHub, example: \"https://github.com/odin-lang/Odin/tree/master/core\"" \
	}
	if c.base_url == "" {
		return "collection requires the key \"base_url\" to be set to the relative URL to your collection, example: \"/core\"" \
	}
	if c.license.text == "" {
		return "collection requires the key \"license.text\" to be set to the name of the license of your collection, example: \"BSD-3-Clause\"" \
	}
	if c.license.url == "" {
		return "collection requires the key \"license.url\" to be set to a URL that points to the license of your collection, example: \"https://github.com/odin-lang/Odin/tree/master/LICENSE\"" \
	}
	if c.root_path == "" {
		return "collection requires the key \"root_path\" to be set to part of the path of all packages in the collection that should be removed, you can use $ODIN_ROOT, or $PWD as variables" \
	}

	if strings.contains_rune(c.name, '/') {
		return "collection name should not contain slashes"
	}

	if !strings.has_prefix(c.base_url, "/") {
		return "collection base_url should start with a slash"
	}

	c.base_url = strings.trim_suffix(c.base_url, "/")
	c.source_url = strings.trim_suffix(c.source_url, "/")

	new_root_path, was_alloc := config_do_replacements(c.root_path)
	if was_alloc do delete(c.root_path)
	c.root_path = new_root_path

	if rm, ok := c.home.embed_readme.?; ok {
		new_rm, was_rm_alloc := config_do_replacements(rm)
		if was_rm_alloc do delete(rm)
		c.home.embed_readme = new_rm
	}

	return nil
}

config_default :: proc() -> (c: Config) {
	err := json.unmarshal(#load("resources/odin-doc.json"), &c)
	fmt.assertf(err == nil, "Unable to load default config: %v", err)
	config_sort_collections(&c)
	return
}

config_merge_from_file :: proc(c: ^Config, file: string) -> (file_ok: bool, err: json.Unmarshal_Error) {
	data: []byte
	data, file_ok = os.read_entire_file_from_filename(file)
	if !file_ok do return

	err = json.unmarshal(data, c)

	if c.hide_core {
		for _, &c in c._collections {
			if c.name == "core" || c.name == "vendor" {
				c.hidden = true
			}
		}
	}

	config_sort_collections(c)
	return
}

config_sort_collections :: proc(c: ^Config) {
	clear(&c.collections)
	for _, &collection in c._collections {
		append(&c.collections, &collection)
	}

	slice.sort_by(
		c.collections[:],
		proc(a, b: ^Collection) -> bool { return a.name < b.name },
	)
}

// Replaces $ODIN_ROOT with ODIN_ROOT, $PWD with the pwd and turns it into an absolute path.
config_do_replacements :: proc(path: string) -> (res: string, allocated: bool) {
	res, allocated = strings.replace(path, "$ODIN_ROOT", ODIN_ROOT, 1)

	if strings.contains(res, "$PWD") {
		@(static) pwd: Maybe(string)
		if pwd == nil {
			pwd = os.get_current_directory()
		}

		resolved_cwd, _ := strings.replace(res, "$PWD", pwd.?, 1)
		if allocated do delete(res)
		res = resolved_cwd
		allocated = true
	}

	abs, errno := os.absolute_path_from_relative(res)
	if errno != os.ERROR_NONE {
		log.warnf("Could not resolve absolute path from %q, errno: %i", res, errno)
		return
	}

	if allocated do delete(res)
	res = abs
	allocated = true

	return
}
