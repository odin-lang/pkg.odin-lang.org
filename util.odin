package odin_html_docs

import doc "core:odin/doc-format"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:slice"
import "core:intrinsics"

GITHUB_LICENSE_URL :: "https://github.com/odin-lang/Odin/tree/master/LICENSE"
GITHUB_CORE_URL    :: "https://github.com/odin-lang/Odin/tree/master/core"
GITHUB_VENDOR_URL  :: "https://github.com/odin-lang/Odin/tree/master/vendor"
BASE_CORE_URL      :: "/core"
BASE_VENDOR_URL    :: "/vendor"

//
// Format Specific
//

// global of things from the file itself
header:   ^doc.Header
files:    []doc.File
pkgs:     []doc.Pkg
entities: []doc.Entity
types:    []doc.Type

// global maps
core_pkgs_to_use:   map[string]^doc.Pkg // trimmed path
vendor_pkgs_to_use: map[string]^doc.Pkg // trimmed path
pkg_to_path:        map[^doc.Pkg]string // trimmed path
pkg_to_collection:  map[^doc.Pkg]^Collection



Collection :: struct {
	name: string,
	pkgs_to_use: ^map[string]^doc.Pkg,
	github_url: string,
	base_url:   string,
	root: ^Dir_Node,

	pkg_entries_map: map[^doc.Pkg]Pkg_Entries,
}

array :: proc(a: $A/doc.Array($T)) -> []T {
	return doc.from_array(header, a)
}
str :: proc(s: $A/doc.String) -> string {
	return doc.from_string(header, s)
}


base_type :: proc(t: doc.Type) -> doc.Type {
	t := t
	for {
		if t.kind != .Named {
			break
		}
		t = types[array(t.types)[0]]
	}
	return t
}

is_type_untyped :: proc(type: doc.Type) -> bool {
	if type.kind == .Basic {
		flags := transmute(doc.Type_Flags_Basic)type.flags
		return .Untyped in flags
	}
	return false
}

is_entity_blank :: proc(e: doc.Entity_Index) -> bool {
	name := str(entities[e].name)
	return name == ""
}



Dir_Node :: struct {
	dir: string,
	path: string,
	name: string,
	pkg: ^doc.Pkg,
	children: [dynamic]^Dir_Node,
}

generate_directory_tree :: proc(pkgs_to_use: map[string]^doc.Pkg) -> (root: ^Dir_Node) {
	sort_tree :: proc(node: ^Dir_Node) {
		slice.sort_by_key(node.children[:], proc(node: ^Dir_Node) -> string {
			return strings.to_lower(node.name, context.temp_allocator)
		})
		for child in node.children {
			sort_tree(child)
		}
	}
	root = new(Dir_Node)
	root.children = make([dynamic]^Dir_Node)
	children := make([dynamic]^Dir_Node)
	for path, pkg in pkgs_to_use {
		dir, _, inner := strings.partition(path, "/")
		if inner == "" {
			node := new_clone(Dir_Node{
				dir  = dir,
				name = dir,
				path = path,
				pkg  = pkg,
			})
			append(&root.children, node)
		} else {
			node := new_clone(Dir_Node{
				dir  = dir,
				name = inner,
				path = path,
				pkg  = pkg,
			})
			append(&children, node)
		}
	}
	child_loop: for child in children {
		dir, _, _ := strings.partition(child.path, "/")
		for node in root.children {
			if node.dir == dir {
				append(&node.children, child)
				continue child_loop
			}
		}
		parent := new_clone(Dir_Node{
			dir  = dir,
			name = dir,
			path = dir,
			pkg  = nil,
		})
		append(&root.children, parent)
		append(&parent.children, child)
	}

	sort_tree(root)

	return
}


//
// General
//

errorf :: proc(format: string, args: ..any) -> ! {
	fmt.eprintf("%s ", os.args[0])
	fmt.eprintf(format, ..args)
	fmt.eprintln()
	os.exit(1)
}


HTML_LESS_THAN :: "&lt;"
HTML_GREATER_THAN :: "&gt;"

// On Unix systems we need to set the directory mode so that we
// can read/write from them
DIRECTORY_MODE :: 0o775 when os.OS == .Darwin || os.OS == .Linux || os.OS == .FreeBSD else 0

common_prefix :: proc(strs: []string) -> string {
	if len(strs) == 0 {
		return ""
	}
	n := max(int)
	for str in strs {
		n = min(n, len(str))
	}

	prefix := strs[0][:n]
	for str in strs[1:] {
		for len(prefix) != 0 && str[:len(prefix)] != prefix {
			prefix = prefix[:len(prefix)-1]
		}
		if len(prefix) == 0 {
			break
		}
	}
	return prefix
}



recursive_make_directory :: proc(path: string, prefix := "") {
	head, _, tail := strings.partition(path, "/")
	path_to_make := head
	if prefix != "" {
		path_to_make = fmt.tprintf("%s/%s", prefix, head)
	}
	os.make_directory(path_to_make, DIRECTORY_MODE)
	if tail != "" {
		recursive_make_directory(tail, path_to_make)
	}
}

escape_html_string :: proc(s: string, allocator := context.allocator) -> string {
	context.allocator = allocator
	escaped, _ := strings.replace_all(s, "<", HTML_LESS_THAN)
	escaped, _ = strings.replace_all(escaped, ">", HTML_GREATER_THAN)
	return escaped
}