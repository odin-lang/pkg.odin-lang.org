package odin_html_docs

import "base:intrinsics"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:log"

import doc "core:odin/doc-format"

array :: proc(a: $A/doc.Array($T)) -> []T {
	return doc.from_array(cfg.header, a)
}

str :: proc(s: $A/doc.String) -> string {
	return doc.from_string(cfg.header, s)
}

base_type :: proc(t: doc.Type) -> doc.Type {
	t := t
	for {
		if t.kind != .Named {
			break
		}
		t = cfg.types[array(t.types)[0]]
	}
	return t
}

type_deref :: proc(t: doc.Type) -> doc.Type {
	bt := base_type(t)
	#partial switch bt.kind {
	case .Pointer:
		return cfg.types[array(bt.types)[0]]
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

is_type_string_or_rune :: proc(type: doc.Type) -> bool {
	type := type
	type = base_type(type)
	if type.kind == .Basic {
		switch str(type.name) {
		case "string", "cstring", "untyped string":
			return true
		case "rune", "untyped rune":
			return true
		}
	}
	return false
}


is_entity_blank :: proc(e: doc.Entity_Index) -> bool {
	name := str(cfg.entities[e].name)
	return name == ""
}

Dir_Node :: struct {
	dir:      string,
	path:     string,
	name:     string,
	pkg:      ^doc.Pkg,
	children: [dynamic]^Dir_Node,
}
sort_directory_tree :: proc(node: ^Dir_Node) {
	slice.sort_by(node.children[:], proc(a, b: ^Dir_Node) -> bool {
		name_cmp := slice.cmp(strings.to_lower(a.name, context.temp_allocator), strings.to_lower(b.name, context.temp_allocator))
		if name_cmp != .Equal {
			return name_cmp == .Less
		}

		return slice.cmp(len(array(a.pkg.entries)), len(array(b.pkg.entries))) != .Less
	})

	// Remove duplicates
	for i := 1; i < len(node.children); /**/ {
		if node.children[i-1].name == node.children[i].name {
			log.infof("duplicate: %v", node.children[i].name)
			ordered_remove(&node.children, i)
		} else {
			i += 1
		}
	}

	for child in node.children {
		sort_directory_tree(child)
	}
}

insert_into_directory_tree :: proc(c: ^Collection, pkgs_to_use: [dynamic]^doc.Pkg) {
	root := c.root
	assert(root != nil)

	children := make([dynamic]^Dir_Node)
	pkgs_to_use_loop: for pkg in pkgs_to_use {
		path, has_pkg := c.pkg_to_path[pkg]
		assert(has_pkg)

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


	sort_directory_tree(root)

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
	os.make_directory(path_to_make)
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
