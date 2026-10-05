package odin_html_docs

import "base:intrinsics"
import "core:fmt"
import "core:io"
import "core:slice"
import "core:strconv"
import "core:strings"

import doc "core:odin/doc-format"

// A procedure bound as an Objective-C method with `@(objc_type=T, objc_name="name")`
Objc_Method :: struct {
	entity:          ^doc.Entity,
	class:           ^Objc_Class,
	name:            string, // its `objc_name`
	is_class_method: bool,
	owned:           bool, // returns an object the caller must release
}

Objc_Class :: struct {
	entity:  ^doc.Entity,
	name:    string, // its `objc_class`, e.g. "MTLBuffer"
	methods: [dynamic]^Objc_Method, // by name
}

Objc_Info :: struct {
	classes:   map[string]^Objc_Class, // by type name
	method_of: map[^doc.Entity]^Objc_Method,
}

objc_info_cache: map[^doc.Pkg]^Objc_Info

objc_info_get :: proc(pkg: ^doc.Pkg) -> ^Objc_Info {
	if info, ok := objc_info_cache[pkg]; ok {
		return info
	}
	info := new(Objc_Info)
	objc_info_cache[pkg] = info

	unquote :: proc(s: string) -> string {
		res, _, ok := strconv.unquote_string(s)
		return res if ok else s
	}
	// Only what this package declares and lists has an entry to link to
	listed :: proc(pkg: ^doc.Pkg, entry: doc.Scope_Entry) -> (e: ^doc.Entity, ok: bool) {
		e = &cfg.entities[entry.entity]
		name := str(entry.name)
		ok = name != "" && name[0] != '_' && name == str(e.name) && &cfg.pkgs[cfg.files[e.pos.file].pkg] == pkg
		return
	}

	types: map[string]^doc.Entity
	defer delete(types)
	for entry in array(pkg.entries) {
		e := listed(pkg, entry) or_continue
		if e.kind != .Type_Name {
			continue
		}
		types[str(e.name)] = e
		if raw, ok := find_entity_attribute(e, "objc_class"); ok {
			info.classes[str(e.name)] = new_clone(Objc_Class{entity = e, name = unquote(raw)})
		}
	}

	for entry in array(pkg.entries) {
		e := listed(pkg, entry) or_continue
		if e.kind != .Procedure && e.kind != .Proc_Group {
			continue
		}
		type_name := find_entity_attribute(e, "objc_type") or_continue
		raw_name  := find_entity_attribute(e, "objc_name") or_continue

		class := info.classes[type_name]
		if class == nil {
			// bound to a type without an `objc_class`
			type_entity := types[type_name] or_continue

			class = new_clone(Objc_Class{entity = type_entity})
			info.classes[type_name] = class
		}

		m := new_clone(Objc_Method{entity = e, class = class, name = unquote(raw_name)})
		is_class_method, _ := find_entity_attribute(e, "objc_is_class_method")
		m.is_class_method = is_class_method == "true"
		m.owned = objc_name_is_owned(m.name) && returns_object(e)
		append(&class.methods, m)
		info.method_of[e] = m
	}

	for _, class in info.classes {
		slice.sort_by(class.methods[:], proc(a, b: ^Objc_Method) -> bool {
			return a.name < b.name
		})
	}
	return info
}

objc_method_of :: proc(pkg: ^doc.Pkg, e: ^doc.Entity) -> ^Objc_Method {
	return objc_info_get(pkg).method_of[e]
}

// The class written as the type `e`, when it has methods or is an Objective-C class
objc_class_of :: proc(pkg: ^doc.Pkg, e: ^doc.Entity) -> ^Objc_Class {
	class := objc_info_get(pkg).classes[str(e.name)]
	if class != nil && class.entity == e {
		return class
	}
	return nil
}

@(private="file")
is_upper :: proc(c: byte) -> bool {
	return c >= 'A' && c <= 'Z'
}
@(private="file")
is_lower :: proc(c: byte) -> bool {
	return c >= 'a' && c <= 'z'
}

proc_tuples :: proc(e: ^doc.Entity) -> (params, results: []doc.Entity_Index) {
	if e.kind == .Proc_Group {
		return
	}
	pt := base_type(cfg.types[e.type])
	if pt.kind != .Proc {
		return
	}
	types := array(pt.types)
	if len(types) > 0 && types[0] != 0 {
		params = array(cfg.types[types[0]].entities)
	}
	if len(types) > 1 && types[1] != 0 {
		results = array(cfg.types[types[1]].entities)
	}
	return
}

// Returns a single object, by pointer
returns_object :: proc(e: ^doc.Entity) -> bool {
	e := e
	if e.kind == .Proc_Group {
		members := array(e.grouped_entities)
		if len(members) == 0 {
			return false
		}
		e = &cfg.entities[members[0]]
	}
	_, results := proc_tuples(e)
	if len(results) != 1 {
		return false
	}
	#partial switch base_type(cfg.types[cfg.entities[results[0]].type]).kind {
	case .Pointer, .Multi_Pointer:
		return true
	}
	return false
}

// Cocoa's rule: a method whose name starts with the word "alloc", "new", "copy" or "mutableCopy"
// returns an object the caller owns, e.g. `newBufferWithLength` but not `newline`
objc_name_is_owned :: proc(name: string) -> bool {
	for prefix in ([]string{"alloc", "new", "copy", "mutableCopy"}) {
		if strings.has_prefix(name, prefix) {
			rest := name[len(prefix):]
			if rest == "" || !is_lower(rest[0]) {
				return true
			}
		}
	}
	return false
}

// Core Foundation's rule, for the plain procedures of a package with Objective-C classes:
// a function with the word "Create" or "Copy" in its name returns an object the caller owns
objc_function_is_owned :: proc(pkg: ^doc.Pkg, e: ^doc.Entity) -> bool {
	has_word :: proc(name, word: string) -> bool {
		for i := 0; i+len(word) <= len(name); i += 1 {
			if name[i:][:len(word)] != word {
				continue
			}
			starts := i == 0 || name[i-1] == '_' || !is_upper(name[i-1])
			ends := i+len(word) == len(name) || !is_lower(name[i+len(word)])
			if starts && ends {
				return true
			}
		}
		return false
	}

	if e.kind != .Procedure {
		return false
	}
	info := objc_info_get(pkg)
	if len(info.classes) == 0 || e in info.method_of {
		return false
	}
	name := str(e.name)
	return (has_word(name, "Create") || has_word(name, "Copy")) && returns_object(e)
}


Objc_Badge :: enum {
	Class_Method,
	Owned,
	Owned_Function,
	Overloaded,
}
Objc_Badges :: bit_set[Objc_Badge]

objc_badges :: proc(pkg: ^doc.Pkg, e: ^doc.Entity) -> (badges: Objc_Badges) {
	m := objc_method_of(pkg, e)
	if m == nil {
		if objc_function_is_owned(pkg, e) {
			badges += {.Owned_Function}
		}
		return
	}
	if m.is_class_method {
		badges += {.Class_Method}
	}
	if m.owned {
		badges += {.Owned}
	}
	if e.kind == .Proc_Group {
		badges += {.Overloaded}
	}
	return
}

OWNED_TITLE          :: "Returns an object you own: release it when you are done with it (the alloc, new, copy and mutableCopy naming rule)"
OWNED_FUNCTION_TITLE :: "Returns an object you own: release it when you are done with it (the Create and Copy naming rule)"

write_objc_badges :: proc(w: io.Writer, badges: Objc_Badges) {
	if .Class_Method in badges {
		io.write_string(w, ` <span class="doc-badge" title="Called on the class rather than on an object">class method</span>`)
	}
	if .Owned in badges {
		fmt.wprintf(w, ` <span class="doc-badge doc-badge-owned" title="%s">owned</span>`, OWNED_TITLE)
	}
	if .Owned_Function in badges {
		fmt.wprintf(w, ` <span class="doc-badge doc-badge-owned" title="%s">owned</span>`, OWNED_FUNCTION_TITLE)
	}
	if .Overloaded in badges {
		io.write_string(w, ` <span class="doc-badge" title="A procedure group of methods with the same name">overloaded</span>`)
	}
}

// The terse form in the Contents panel, e.g. "class · owned"
write_objc_toc_badges :: proc(w: io.Writer, badges: Objc_Badges) {
	words: [dynamic]string
	words.allocator = context.temp_allocator
	if .Class_Method in badges {
		append(&words, "class")
	}
	if .Owned in badges || .Owned_Function in badges {
		append(&words, "owned")
	}
	if len(words) > 0 {
		fmt.wprintf(w, `<span class="toc-badge">%s</span>`, strings.join(words[:], " &middot; ", context.temp_allocator))
	}
}


// A variable for an object of a class: `RenderCommandEncoder` is `renderCommandEncoder`, `URLRequest` is `urlRequest`
objc_variable_name :: proc(type_name: string) -> string {
	n := 0
	for n < len(type_name) && is_upper(type_name[n]) {
		n += 1
	}
	if n > 1 && n < len(type_name) {
		n -= 1 // the next word's capital
	}
	b := strings.builder_make(context.temp_allocator)
	for i in 0..<n {
		strings.write_byte(&b, type_name[i] + ('a' - 'A'))
	}
	strings.write_string(&b, type_name[n:])
	name := strings.to_string(b)

	switch name {
	case "string":
		return "str"
	case "any", "bool", "byte", "cstring",
	     "int", "map", "matrix", "proc", "rawptr",
	     "rune", "struct", "typeid", "uint", "union", "enum", "context":
		return "self"
	}
	return name
}

// The names a call's results are assigned to
@(private="file")
objc_result_names :: proc(m: ^Objc_Method, e: ^doc.Entity, receiver: string, args, results: []doc.Entity_Index) -> []string {
	// `^Buffer` is "Buffer"
	base_type_named :: proc(t: doc.Type) -> string {
		t := t
		if t.kind == .Pointer || t.kind == .Multi_Pointer {
			t = cfg.types[array(t.types)[0]]
		}
		if t.kind != .Named {
			return ""
		}
		name := str(t.name)
		if n := strings.index_byte(name, '('); n >= 0 {
			name = name[:n]
		}
		if strings.has_prefix(name, "objc_") {
			return "" // intrinsics.objc_object says nothing of what it is
		}
		return name
	}

	names := make([]string, len(results), context.temp_allocator)
	if len(results) > 1 {
		for r, i in results {
			name := str(cfg.entities[r].name)
			names[i] = name if name != "" && name != "_" else fmt.tprintf("res%d", i)
		}
		return names
	}
	if len(results) == 0 {
		return names
	}

	name := str(cfg.entities[results[0]].name)
	if name == "" || name == "_" {
		name = "res"
		result_type := base_type_named(cfg.types[cfg.entities[results[0]].type])
		if len(args) == 0 && !m.is_class_method && !m.owned && !strings.has_prefix(m.name, "init") {
			// a getter: `label := resource->label()`
			name = m.name
		} else if result_type != "" {
			// `buffer := device->newBufferWithLength(length, options)`
			name = objc_variable_name(result_type)
		}
	}
	if name == receiver {
		name = "res"
	}
	for a in args {
		if str(cfg.entities[a].name) == name {
			name = "res"
		}
	}
	names[0] = name
	return names
}

// How a method is called from Odin: `buffer := device->newBufferWithLength(length, options)`
write_objc_call_line :: proc(w: io.Writer, m: ^Objc_Method, e: ^doc.Entity) {
	params, results := proc_tuples(e)
	args := params
	if !m.is_class_method && len(args) > 0 {
		args = args[1:] // self
	}
	class_name := str(m.class.entity.name)
	receiver := "" if m.is_class_method else objc_variable_name(class_name)

	arg_names := make([]string, len(args), context.temp_allocator)
	for a, i in args {
		name := str(cfg.entities[a].name)
		arg_names[i] = name if name != "" && name != "_" else fmt.tprintf("arg%d", i)
	}
	result_names := objc_result_names(m, e, receiver, args, results)

	width := 0
	if len(result_names) > 0 {
		assigned := strings.join(result_names, ", ", context.temp_allocator)
		fmt.wprintf(w, "%s := ", assigned)
		width += len(assigned) + len(" := ")
	}
	if m.is_class_method {
		fmt.wprintf(w, `<a class="code-typename" href="#{0:s}">{0:s}</a>.`, class_name)
		width += len(class_name) + 1
	} else {
		fmt.wprintf(w, "%s-&gt;", receiver)
		width += len(receiver) + 2
	}
	fmt.wprintf(w, `<a class="code-procedure" href="#%s">%s</a>(`, str(e.name), m.name)
	width += len(m.name) + 1

	joined := strings.join(arg_names, ", ", context.temp_allocator)
	if len(arg_names) > 1 && width+len(joined)+1 > MAX_SIGNATURE_WIDTH {
		io.write_string(w, "\n")
		for name in arg_names {
			fmt.wprintf(w, "\t%s,\n", name)
		}
	} else {
		io.write_string(w, joined)
	}
	io.write_string(w, ")")
}

// How a method is called, written under its signature
write_objc_call :: proc(w: io.Writer, pkg: ^doc.Pkg, e: ^doc.Entity) {
	m := objc_method_of(pkg, e)
	if m == nil {
		return
	}
	io.write_string(w, `<pre class="doc-code doc-objc-call">`)
	if e.kind == .Proc_Group {
		for member, i in array(e.grouped_entities) {
			if i > 0 {
				io.write_byte(w, '\n')
			}
			write_objc_call_line(w, m, &cfg.entities[member])
		}
	} else {
		write_objc_call_line(w, m, e)
	}
	io.write_string(w, "</pre>\n")
}


// The methods bound to a class and to each class it inherits from, with a short signature each
write_objc_methods :: proc(w: io.Writer, page_pkg, pkg: ^doc.Pkg, class_entity: ^doc.Entity, names_seen: ^map[string]bool, is_inherited := false) {
	collection := cfg.pkg_to_collection[pkg]
	if collection == nil {
		return
	}
	base := fmt.tprintf("%s/%s/", collection.base_url, collection.pkg_to_path[pkg])
	class_name := str(class_entity.name)
	if pkg != page_pkg {
		class_name = fmt.tprintf("%s.%s", pkg_import_name(pkg), class_name)
	}

	writer := &Type_Writer{
		w   = w,
		pkg = doc.Pkg_Index(intrinsics.ptr_sub(page_pkg, &cfg.pkgs[0])),
	}
	defer delete(writer.generic_scope)

	listed := make([dynamic]^Objc_Method, context.temp_allocator)
	name_width := 0
	if class := objc_class_of(pkg, class_entity); class != nil {
		for m in class.methods do if !names_seen[m.name] {
			names_seen[m.name] = true
			append(&listed, m)
			name_width = max(name_width, len(m.name))
		}
	}

	if len(listed) > 0 {
		if is_inherited {
			fmt.wprintf(w, `<h5>Methods Inherited From <a href="%s#%s">%s</a></h5>`+"\n", base, str(class_entity.name), class_name)
		} else {
			fmt.wprintln(w, "<h4>Bound Objective-C Methods</h4>")
		}
		fmt.wprintln(w, `<ul class="doc-objc-methods">`)
		for m in listed {
			fmt.wprintf(w, `<li><a class="code-procedure" href="%s#%s">%s</a>`, base, str(m.entity.name), m.name)
			// padded so the signatures line up
			for _ in len(m.name)..<name_width {
				io.write_byte(w, ' ')
			}

			params, results := proc_tuples(m.entity)
			if m.entity.kind == .Proc_Group {
				io.write_string(w, "(…)")
			} else {
				if !m.is_class_method && len(params) > 0 {
					params = params[1:]
				}
				io.write_byte(w, '(')
				for p, i in params {
					if i > 0 {
						io.write_string(w, ", ")
					}
					io.write_string(w, str(cfg.entities[p].name))
				}
				io.write_byte(w, ')')
				if len(results) > 0 {
					// the parameters declare the `$T` the results use
					pt := base_type(cfg.types[m.entity.type])
					clear(&writer.generic_scope)
					scratch := strings.builder_make(context.temp_allocator)
					writer.w = strings.to_writer(&scratch)
					write_type(writer, cfg.types[array(pt.types)[0]], {})
					writer.w = w

					io.write_string(w, " -&gt; ")
					write_type(writer, cfg.types[array(pt.types)[1]], {.Is_Results})
				}
			}
			write_objc_badges(w, objc_badges(pkg, m.entity))
			io.write_string(w, "</li>\n")
		}
		fmt.wprintln(w, "</ul>")
	}

	// the superclass first
	parents := objc_parents(class_entity)
	#reverse for parent in parents {
		write_objc_methods(w, page_pkg, parent.pkg, parent.entity, names_seen, true)
	}
}

Objc_Parent :: struct {
	entity: ^doc.Entity,
	pkg:    ^doc.Pkg,
}

// What a class inherits from with `using _: Parent`, up to but not including intrinsics.objc_object.
// The last is its superclass, those before it are protocols such as `NS.Copying(T)`.
objc_parents :: proc(class_entity: ^doc.Entity) -> []Objc_Parent {
	t := base_type(cfg.types[class_entity.type])
	if t.kind != .Struct {
		return nil
	}
	parents := make([dynamic]Objc_Parent, context.temp_allocator)
	for field_index in array(t.entities) {
		field := &cfg.entities[field_index]
		field_type := cfg.types[field.type]
		if .Param_Using in field.flags && field_type.kind == .Named && field_type.entities.length > 0 {
			e := &cfg.entities[array(field_type.entities)[0]]
			e_pkg := &cfg.pkgs[cfg.files[e.pos.file].pkg]
			if cfg.pkg_to_collection[e_pkg] != nil {
				append(&parents, Objc_Parent{e, e_pkg})
			}
		}
	}
	return parents[:]
}

objc_superclass :: proc(class_entity: ^doc.Entity) -> (superclass: Objc_Parent, ok: bool) {
	parents := objc_parents(class_entity)
	if len(parents) == 0 {
		return
	}
	return parents[len(parents)-1], true
}

// What hovering a class shows: its definition, its Objective-C name, what it inherits and how many methods it has
write_objc_class_preview :: proc(w: io.Writer, page_pkg: ^doc.Pkg, class: ^Objc_Class, definition: string) {
	io.write_string(w, definition)
	if class.name != "" {
		fmt.wprintf(w, "\n<span class=\"comment\">// Objective-C class %s</span>", class.name)
	}

	if parent, ok := objc_superclass(class.entity); ok {
		io.write_string(w, "\n<span class=\"comment\">// Inherits ")
		for depth := 0; ok && depth < 16; depth += 1 {
			if depth > 0 {
				io.write_string(w, " → ")
			}
			if parent.pkg != page_pkg {
				fmt.wprintf(w, "%s.", pkg_import_name(parent.pkg))
			}
			parent_name := str(parent.entity.name)
			if n := strings.index_byte(parent_name, '('); n >= 0 {
				parent_name = parent_name[:n] // `Copying($T=Texture)` is `Copying`
			}
			io.write_string(w, parent_name)
			parent, ok = objc_superclass(parent.entity)
		}
		io.write_string(w, "</span>")
	}

	if methods := len(class.methods); methods > 0 {
		fmt.wprintf(w, "\n<span class=\"comment\">// %d method%s</span>", methods, "" if methods == 1 else "s")
	}
}

// Apple's documentation of an Objective-C class, as configured by `objc_docs`
objc_doc_url :: proc(pkg: ^doc.Pkg, class_name: string) -> string {
	if cfg.objc_docs.url == "" || class_name == "" {
		return ""
	}
	framework, ok := cfg.objc_docs.classes[class_name]
	if !ok {
		framework, ok = cfg.objc_docs.packages[pkg_import_path(pkg)]
	}
	if !ok || framework == "" {
		return ""
	}
	page := strings.to_lower(class_name, context.temp_allocator)
	if n := strings.index_byte(framework, '/'); n >= 0 {
		framework, page = framework[:n], framework[n+1:]
	}
	url, _ := strings.replace_all(cfg.objc_docs.url, "{framework}", framework, context.temp_allocator)
	url, _  = strings.replace_all(url, "{class}", page, context.temp_allocator)
	return url
}


// The package whose Contents panel is being written, for its classes to list their methods
toc_pkg: ^doc.Pkg

// A procedure listed under its class in the Contents panel rather than under Procedures
objc_listed_under_class :: proc(pkg: ^doc.Pkg, entry: doc.Scope_Entry, class_names: map[string]bool) -> bool {
	e := &cfg.entities[entry.entity]
	m := objc_method_of(pkg, e)
	return m != nil && str(entry.name) == str(e.name) && str(m.class.entity.name) in class_names
}

write_toc_type_item :: proc(w: io.Writer, entry: doc.Scope_Entry) {
	e := &cfg.entities[entry.entity]
	class := objc_class_of(toc_pkg, e) if str(entry.name) == str(e.name) else nil
	if class == nil || len(class.methods) == 0 {
		write_index_item(w, entry)
		return
	}

	name := str(entry.name)
	fmt.wprintf(w, `<li class="toc-class"><button type="button" class="toc-class-toggle" aria-expanded="false" aria-label="Methods of %s"></button>`, name)
	fmt.wprintf(w, `<a href="#%s">`, name)
	write_breakable_name(w, name)
	fmt.wprintf(w, `<span class="toc-count">%d</span></a>`+"\n", len(class.methods))
	fmt.wprintln(w, "<ul>")
	for m in class.methods {
		fmt.wprintf(w, `<li><a href="#%s">%s`, str(m.entity.name), m.name)
		write_objc_toc_badges(w, objc_badges(toc_pkg, m.entity))
		io.write_string(w, "</a></li>\n")
	}
	io.write_string(w, "</ul></li>\n")
}
