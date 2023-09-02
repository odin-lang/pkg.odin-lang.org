package odin_html_docs

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

import doc "core:odin/doc-format"

Config :: struct {
	hide_core:         bool,
	collections:       map[string]Collection,

	// -- Start non configurable --
	header:            ^doc.Header,
	files:             []doc.File,
	pkgs:              []doc.Pkg,
	entities:          []doc.Entity,
	types:             []doc.Type,
	pkg_to_collection: map[^doc.Pkg]^Collection,
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

	resolved_root, was_alloc := strings.replace(c.root_path, "$ODIN_ROOT", ODIN_ROOT, 1)
	if was_alloc {
		delete(c.root_path)
		c.root_path = resolved_root
	}

	if strings.contains(c.root_path, "$PWD") {
		@(static) pwd: Maybe(string)
		if pwd == nil {
			pwd = os.get_current_directory()
		}

		resolved_cwd, _ := strings.replace(c.root_path, "$PWD", pwd.?, 1)
		delete(c.root_path)
		c.root_path = resolved_cwd
	}

	return nil
}

config_default :: proc() -> (c: Config) {
	err := json.unmarshal(#load("resources/odin-doc.json"), &c)
	fmt.assertf(err == nil, "Unable to load default config: %v", err)
	return
}

config_merge_from_file :: proc(c: ^Config, file: string,) -> (file_ok: bool, err: json.Unmarshal_Error) {
	data: []byte
	data, file_ok = os.read_entire_file_from_filename(file)
	if !file_ok do return

	err = json.unmarshal(data, c)

	if c.hide_core {
		for _, &c in c.collections {
			if c.name == "core" || c.name == "vendor" {
				c.hidden = true
			}
		}
	}

	return
}
