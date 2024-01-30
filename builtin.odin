package odin_html_docs

import "core:fmt"
import "core:io"
import "core:slice"
import "core:strings"

import doc "core:odin/doc-format"

Builtin :: struct {
	name:    string,
	kind:    string,
	type:    string,
	comment: string,
	value:   string,
}

builtins := []Builtin{
	{name = "nil",          kind = "c", type = "untyped nil", comment = "`nil` is a predecared identifier representing the zero value for a pointer, multi-pointer, enum, bit_set, slice, dynamic array, map, procedure, any, typeid, cstring, union, #soa array, #soa pointer, #relative type"},
	{name = "false",        kind = "c", type = "untyped boolean", value = "0 != 0"},
	{name = "true",         kind = "c", type = "untyped boolean", value = "0 == 0"},

	{name = "ODIN_OS",      kind = "c", type = "runtime.Odin_OS_Type",     comment = "An enum value specifying the target platform's operating system."},
	{name = "ODIN_ARCH",    kind = "c", type = "runtime.Odin_Arch_Type",   comment = "An enum value specifying the target platform's architecture."},
	{name = "ODIN_ENDIAN",  kind = "c", type = "runtime.Odin_Endian_Type", comment = "An enum value specifying the target platform's endiannes."},
	{name = "ODIN_VENDOR",  kind = "c", type = "untyped string",           comment = "A string specifying the current Odin compiler vendor."},
	{name = "ODIN_VERSION", kind = "c", type = "untyped string",           comment = "A string specifying the current Odin version."},
	{name = "ODIN_ROOT",    kind = "c", type = "untyped string",           comment = "The path to the root Odin directory."},
	{name = "ODIN_DEBUG",   kind = "c", type = "untyped boolean",          comment = "Equal to `true` if the `-debug` flag has been set during compilation, otherwise `false`."},

	{name = "byte", kind = "t", value = "u8", comment = "`byte` is an alias for `u8` and is equivalent to `u8` in all ways. It is used as a convention to distinguish values from 8-bit unsigned integer values."},

	{name = "bool", kind = "t", comment = "`bool` is the set of boolean values, `false` and `true`. This is distinct to `b8`. `bool` has a size of 1 byte (8 bits)."},
	{name = "b8",   kind = "t", comment = "`b8` is the set of boolean values, `false` and `true`. This is distinct to `bool`. `b8` has a size of 1 byte (8 bits)."},
	{name = "b16",  kind = "t", comment = "`b16` is the set of boolean values, `false` and `true`. `b16` has a size of 2 bytes (16 bits)."},
	{name = "b32",  kind = "t", comment = "`b32` is the set of boolean values, `false` and `true`. `b32` has a size of 4 bytes (32 bits)."},
	{name = "b64",  kind = "t", comment = "`b64` is the set of boolean values, `false` and `true`. `b64` has a size of 8 bytes (64 bits)."},

	{name = "i8", kind = "t",  comment = "`i8` is the set of all signed 8-bit integers. Range -128 through 127."},
	{name = "u8", kind = "t",  comment = "`u8` is the set of all unsigned 8-bit integers. Range 0 through 255."},
	{name = "i16", kind = "t", comment = "`i16` is the set of all signed 16-bit integers with native endianness. Range -32768 through 32767."},
	{name = "u16", kind = "t", comment = "`u16` is the set of all unsigned 16-bit integers with native endianness. Range 0 through 65535."},
	{name = "i32", kind = "t", comment = "`i32` is the set of all signed 32-bit integers with native endianness. Range -2147483648 through 2147483647."},
	{name = "u32", kind = "t", comment = "`u32` is the set of all unsigned 32-bit integers with native endianness. Range 0 through 4294967295."},
	{name = "i64", kind = "t", comment = "`i64` is the set of all signed 64-bit integers with native endianness. Range -9223372036854775808 through 9223372036854775807."},
	{name = "u64", kind = "t", comment = "`u64` is the set of all unsigned 64-bit integers with native endianness. Range 0 through 18446744073709551615."},

	{name = "i128", kind = "t", comment = "`i128` is the set of all signed 128-bit integers with native endianness. Range -170141183460469231731687303715884105728 through 170141183460469231731687303715884105727."},
	{name = "u128", kind = "t", comment = "`u128` is the set of all unsigned 128-bit integers with native endianness. Range 0 through 340282366920938463463374607431768211455."},

	{name = "rune", kind = "t", comment = "`rune` is the set of all Unicode code points. It is internally the same as `i32` but distinct."},

	{name = "f16", kind = "t", comment = "`f16` is the set of all IEEE-754 16-bit floating-point numbers with native endianness."},
	{name = "f32", kind = "t", comment = "`f32` is the set of all IEEE-754 32-bit floating-point numbers with native endianness."},
	{name = "f64", kind = "t", comment = "`f64` is the set of all IEEE-754 64-bit floating-point numbers with native endianness."},

	{name = "complex32",  kind = "t", comment = "`complex32` is the set of all complex numbers with `f16` real and imaginary parts"},
	{name = "complex64",  kind = "t", comment = "`complex64` is the set of all complex numbers with `f32` real and imaginary parts"},
	{name = "complex128", kind = "t", comment = "`complex128` is the set of all complex numbers with `f64` real and imaginary parts"},

	{name = "quaternion64",  kind = "t", comment = "`quaternion64` is the set of all complex numbers with `f16` real and imaginary (i, j, & k) parts"},
	{name = "quaternion128", kind = "t", comment = "`quaternion128` is the set of all complex numbers with `f32` real and imaginary (i, j, & k) parts"},
	{name = "quaternion256", kind = "t", comment = "`quaternion256` is the set of all complex numbers with `f64` real and imaginary (i, j, & k) parts"},

	{name = "int",     kind = "t", comment = "`int` is a signed integer type that is at least 32 bits in size. It is a distinct type, however, and not an alias for say, `i32`."},
	{name = "uint",    kind = "t", comment = "`uint` is an unsigned integer type that is at least 32 bits in size. It is a distinct type, however, and not an alias for say, `u32`."},
	{name = "uintptr", kind = "t", comment = "`uintptr` is an unsigned integer type that is large enough to hold the bit pattern of any pointer."},

	{name = "rawptr",  kind = "t", comment = "`rawptr` represents a pointer to an arbitrary type. It is equivalent to `void *` in C."},

	{name = "string",  kind = "t", comment = "`string` is the set of all strings of 8-bit bytes, conventionally but not necessarily representing UTF-8 encoding text. A `string` may be empty but not `nil`. Elements of `string` type are immutable and indexable."},
	{name = "cstring", kind = "t", comment = "`cstring` is the set of all strings of 8-bit bytes terminated with a NUL (0) byte, conventionally but not necessarily representing UTF-8 encoding text. A `cstring` may be empty or `nil`. Elements of `string` type are immutable but not indexable."},

	{name = "typeid", kind = "t", comment = "`typeid` is a unique identifier for an Odin type at runtime. It can be mapped to relevant type information through `type_info_of`."},
	{name = "any",    kind = "t",
		comment = "`any` can reference any data type at runtime. Internally it contains a pointer to the underlying data and its relevant `typeid`. This is a very useful construct in order to have a runtime type safe printing procedure.\n\n" +
		          "**Note:** The `any` value is only valid for as long as the underlying data is still valid. Passing a literal to an `any` will allocate the literal in the current stack frame.\n\n" +
		          "**Note:** It is highly recommend that you **do not** use this unless you know what you are doing. Its primary use is for printing procedures.",
	},

	// Endian Specific Types
	{name = "i16le",  kind = "t", comment = "`i16le` is the set of all signed 16-bit integers with little endianness. Range -32768 through 32767."},
	{name = "u16le",  kind = "t", comment = "`u16le` is the set of all unsigned 16-bit integers with little endianness. Range 0 through 65535."},
	{name = "i32le",  kind = "t", comment = "`i32le` is the set of all signed 32-bit integers with little endianness. Range -2147483648 through 2147483647."},
	{name = "u32le",  kind = "t", comment = "`u32le` is the set of all unsigned 32-bit integers with little endianness. Range 0 through 4294967295."},
	{name = "i64le",  kind = "t", comment = "`i64le` is the set of all signed 64-bit integers with little endianness. Range -9223372036854775808 through 9223372036854775807."},
	{name = "u64le",  kind = "t", comment = "`u64le` is the set of all unsigned 64-bit integers with little endianness. Range 0 through 18446744073709551615."},
	{name = "i128le", kind = "t", comment = "`i128le` is the set of all signed 128-bit integers with little endianness. Range -170141183460469231731687303715884105728 through 170141183460469231731687303715884105727."},
	{name = "u128le", kind = "t", comment = "`u128le` is the set of all unsigned 128-bit integers with little endianness. Range 0 through 340282366920938463463374607431768211455."},

	{name = "i16be",  kind = "t", comment = "`i16be` is the set of all signed 16-bit integers with big endianness. Range -32768 through 32767."},
	{name = "u16be",  kind = "t", comment = "`u16be` is the set of all unsigned 16-bit integers with big endianness. Range 0 through 65535."},
	{name = "i32be",  kind = "t", comment = "`i32be` is the set of all signed 32-bit integers with big endianness. Range -2147483648 through 2147483647."},
	{name = "u32be",  kind = "t", comment = "`u32be` is the set of all unsigned 32-bit integers with big endianness. Range 0 through 4294967295."},
	{name = "i64be",  kind = "t", comment = "`i64be` is the set of all signed 64-bit integers with big endianness. Range -9223372036854775808 through 9223372036854775807."},
	{name = "u64be",  kind = "t", comment = "`u64be` is the set of all unsigned 64-bit integers with big endianness. Range 0 through 18446744073709551615."},
	{name = "i128be", kind = "t", comment = "`i128be` is the set of all signed 128-bit integers with big endianness. Range -170141183460469231731687303715884105728 through 170141183460469231731687303715884105727."},
	{name = "u128be", kind = "t", comment = "`u128be` is the set of all unsigned 128-bit integers with big endianness. Range 0 through 340282366920938463463374607431768211455."},


	{name = "f16le", kind = "t", comment = "`f16le` is the set of all IEEE-754 16-bit floating-point numbers with little endianness."},
	{name = "f32le", kind = "t", comment = "`f32le` is the set of all IEEE-754 32-bit floating-point numbers with little endianness."},
	{name = "f64le", kind = "t", comment = "`f64le` is the set of all IEEE-754 64-bit floating-point numbers with little endianness."},

	{name = "f16be", kind = "t", comment = "`f16be` is the set of all IEEE-754 16-bit floating-point numbers with big endianness."},
	{name = "f32be", kind = "t", comment = "`f32be` is the set of all IEEE-754 32-bit floating-point numbers with big endianness."},
	{name = "f64be", kind = "t", comment = "`f64be` is the set of all IEEE-754 64-bit floating-point numbers with big endianness."},

	// Procedures
	{name = "len", kind = "b", type = "proc(v: Array_Type) -> int",
		comment = "The `len` built-in procedure returns the length of `v` according to its type:\n" +
		          "\n" +
		          "\tArray: the number of elements in v.\n" +
		          "\tPointer to (any) array: the number of elements in `v^` (even if `v` is `nil`).\n" +
		          "\tSlice, dynamic array, or map: the number of elements in `v`; if `v` is `nil`, `len(v)` is zero.\n" +
		          "\tString: the number of bytes in `v`\n" +
		          "\tEnumerated array: the number elements in v.`\n" +
		          "\tEnum type: the number of enumeration fields.\n"+
		          "\t#soa array: the number of elements in `v`; if `v` is `nil`, `len(v)` is zero.\n"+
		          "\t#simd vector: the number of elements in `v`.\n"+
		          "\n" +
		          "For some arguments, such as a string literal or a simple array expression, the result can be constant.",
	},
	{name = "cap", kind = "b", type = "proc(v: Array_Type) -> int",
		comment = "The `cap` built-in procedure returns the length of `v` according to its type:\n" +
		          "\n" +
		          "\tArray: the number of elements in v.\n" +
		          "\tPointer to (any) array: the number of elements in `v^` (even if `v` is `nil`).\n" +
		          "\tDynamic array, or map: the reserved number of elements in `v`; if `v` is `nil`, `len(v)` is zero.\n" +
		          "\tEnum type: equal to `max(Enum)-min(Enum)+1`.\n"+
		          "\t#soa dynamic array: the reserved number of elements in `v`; if `v` is `nil`, `len(v)` is zero.\n"+
		          "\n" +
		          "For some arguments, such as a string literal or a simple array expression, the result can be constant.",
	},

	{name = "size_of", kind = "b", type = "proc($T: typeid) -> int",
		comment = "`size_of` takes an expression or type, and returns the size in bytes of the type of the expression if it was hypothetically instantiated as a variable. " +
		"The size does not include any memory possibly referenced by a value. For instance, if a slice was given, `size_of` returns the size of the internal slice data structure and not the size of the memory referenced by the slice. " +
		"For a struct, the size includes any padding introduced by field alignment (if not specified with `#packed`. " +
		"Other types follow similar rules. " +
		"The return value of `size_of` is a compile time known integer constant.",
	},
	{name = "align_of", kind = "b", type = "proc($T: typeid) -> int",
		comment = "`align_of` takes an expression or type, and returns the alignment in bytes of the type of the expression if it was hypothetically instantiated as a variable `v`. " +
		          "It is the largest value `m` such that the address of `v` is always `0 mod m`.",
	},

	{name = "offset_of",           kind = "b", type = "proc{offset_of_selector, offset_of_member}",  comment = "`offset_of` returns the offset in bytes with the struct of the field."},
	{name = "offset_of_selector",  kind = "b", type = "proc(selector: $T) -> uintptr",               comment = `e.g. offset_of(t.f), where t is an instance of the type T`},
	{name = "offset_of_member"  ,  kind = "b", type = "proc($T: typeid, member: $M) -> uintptr",     comment = `e.g. offset_of(T, f), where T can be the type instead of a variable`},
	{name = "offset_of_by_string", kind = "b", type = "proc($T: typeid, member: string) -> uintptr", comment = `e.g. offset_of(T, "f"), where T can be the type instead of a variable`},

	{name = "type_of",      kind = "b", type = "proc(x: expr) -> type",                  comment = "`type_of` returns the type of a given expression"},
	{name = "type_info_of", kind = "b", type = "proc($T: typeid) -> ^runtime.Type_Info", comment = "`type_info_of` returns the runtime type information from a given `typeid`."},
	{name = "typeid_of",    kind = "b", type = "proc($T: typeid) -> typeid",             comment = "`typeid_of` returns the associated runtime known `typeid` of the specified type."},

	{name = "swizzle", kind = "b", type = "proc(x: [N]T, indices: ..int) -> [len(indices)]T"},

	{name = "complex",    kind = "b", type = "proc(real, imag: Float) -> Complex_Type"},
	{name = "quaternion", kind = "b", type = "proc(real, imag, jmag, kmag: Float) -> Quaternion_Type"},
	{name = "real",       kind = "b", type = "proc(v: Complex_Or_Quaternion) -> Float", comment = "`real` returns the real part of a complex or quaternion number `v`. The return value will be the floating-point type corresponding to the type of `v`."},
	{name = "imag",       kind = "b", type = "proc(v: Complex_Or_Quaternion) -> Float", comment = "`imag` returns the i-imaginary part of a complex or quaternion number `v`. The return value will be the floating-point type corresponding to the type of `v`."},
	{name = "jmag",       kind = "b", type = "proc(v: Quaternion) -> Float",            comment = "`jmag` returns the j-imaginary part of a quaternion number `v`. The return value will be the floating-point type corresponding to the type of `v`."},
	{name = "kmag",       kind = "b", type = "proc(v: Quaternion) -> Float",            comment = "`jmag` returns the j-imaginary part of a quaternion number `v`. The return value will be the floating-point type corresponding to the type of `v`."},
	{name = "conj",       kind = "b", type = "proc(v: Complex_Or_Quaternion) -> Complex_Or_Quaternion", comment = "`conj` returns the complex conjugate of a complex or quaternion number `v`. This negates the imaginary component(s) whilst keeping the real component untouched."},

	{name = "expand_values", kind = "b", type = "proc(value: Struct_Or_Array) -> (A, B, C, ...)", comment = "`expand_values` will return multiple values corresponding to the multiple fields of the passed struct or the multiple elements of a passed fixed length array."},

	{name = "min",       kind = "b", type = "proc(values: ..T) -> T",
		comment = "`min` returns the minimum value of passed arguments of all the same type.\n" +
		          "If one argument is passed and it is an enum type, then `min` returns the minimum value of the fields of that enum type.",
	},
	{name = "max",       kind = "b", type = "proc(values: ..T) -> T",
		comment = "`max` returns the maximum value of passed arguments of all the same type.\n" +
		          "If one argument is passed and it is an enum type, then `max` returns the maximum value of the fields of that enum type.",
	},
	{name = "abs",       kind = "b", type = "proc(value: T) -> T",
		comment = "`abs` returns the absolute value of passed argument.\n" +
		          "If the argument is a complex or quaternion, this is equivalent to `real(conj(value) * value)`.",
	},
	{name = "clamp",     kind = "b", type = "proc(v, minimum, maximum: T) -> T",
		comment = "`clamp` returns a value `v` clamped between `minimum` and `maximum`.\n" +
		          "This is calculated as the following: `minimum if v < minimum else maximum if v > maximum else v`.",
	},

	{name = "soa_zip",   kind = "b", type = "proc(slices: ...) -> #soa[]Struct", comment = "See: [[https://odin-lang.org/docs/overview/#soa_zip-and-soa_unzip]]"},
	{name = "soa_unzip", kind = "b", type = "proc(value: $S/#soa[]$E) -> (slices: ...)", comment = "See: [[https://odin-lang.org/docs/overview/#soa_zip-and-soa_unzip]]"},

	{name = "raw_data", kind = "b", type = "proc(value: $T) -> [^]$E",
		comment = "`raw_data` returns the underlying data of a built-in data type as a [[multi-pointer ; https://odin-lang.org/docs/overview/#multi-pointers]].\n\n" +
		          "\traw_data([]$E)         -> [^]E    // slices\n" +
		          "\traw_data([dynamic]$E)  -> [^]E    // dynamic arrays\n" +
		          "\traw_data(^[$N]$E)      -> [^]E    // fixed array and enumerated arrays \n" +
		          "\traw_data(^#simd[$N]$E) -> [^]E    // simd vectors \n" +
		          "\traw_data(string)       -> [^]byte // string\n" +
		          "",
	},

}

builtin_docs := `package builtin provides documentation for Odin's predeclared identifiers. The items documented here are not actually in package builtin but here to allow for better documentation for the language's special identifiers.`

write_builtin_pkg :: proc(w: io.Writer, dir, path: string, runtime_pkg: ^doc.Pkg, collection: ^Collection) {
	// slice.sort_by(builtins, proc(a, b: Builtin) -> bool {
	// 	if a.kind == b.kind {
	// 		return a.name < b.name
	// 	}
	// 	return a.kind < b.kind
	// })

	fmt.wprintln(w, `<div class="row odin-main" id="pkg">`)
	defer fmt.wprintln(w, `</div>`)

	write_pkg_sidebar(w, nil, collection)

	fmt.wprintln(w, `<article class="col-lg-8 p-4 documentation odin-article">`)

	write_breadcrumbs(w, path, runtime_pkg, collection)

	fmt.wprintf(w, "<h1>package %s:%s", strings.to_lower(collection.name, context.temp_allocator), path)

	pkg_src_url := fmt.tprintf("%s/%s", collection.source_url, path)
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
			e := &cfg.entities[entry.entity]
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
					e := &cfg.entities[entry.entity]
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
		
		collection := cfg.pkg_to_collection[runtime_pkg]
		runtime_url := fmt.aprintf("%s/%s", collection.base_url, collection.pkg_to_path[runtime_pkg])
		defer delete(runtime_url)

		// builtin entries
		for b in builtins do if b.kind == kind {
			fmt.wprintln(w, `<div class="pkg-entity">`)
			defer fmt.wprintln(w, `</div>`)

			name := b.name

			fmt.wprintf(w, "<h3 id=\"{0:s}\"><span><a class=\"doc-id-link\" href=\"#{0:s}\">{0:s}", name)
			fmt.wprintf(w, "<span class=\"a-hidden\">&nbsp;¶</span></a></span>")
			fmt.wprintf(w, "</h3>\n")
			fmt.wprintln(w, `<div>`)

			the_comment := b.comment
			extra_comment := ""

			switch b.kind {
			case "c", "t":
				fmt.wprint(w, `<pre class="doc-code">`)
				if strings.contains(b.type, ".") {
					pkg, _, type := strings.partition(b.type, ".")
					if pkg == str(runtime_pkg.name) {
						fmt.wprintf(w, `{0:s} : {2:s}.<a href="{1:s}#{3:s}">{3:s}</a> : `, name, runtime_url, pkg, type)

						for entry in array(runtime_pkg.entries) {
							e := &cfg.entities[entry.entity]
							if e.kind == .Type_Name && str(e.name) == type {
								extra_comment = strings.trim_space(str(e.docs))
								if extra_comment == "" {
									extra_comment = strings.trim_space(str(e.comment))
								}
								break
							}
						}
					} else {
						fmt.wprintf(w, "%s :: ", name)
					}
				} else {
					fmt.wprintf(w, "%s :: ", name)
				}
				fmt.wprintf(w, "%s", b.value if len(b.value) != 0 else
				                     "…"     if b.kind == "c"     else
				                     name)
				if strings.contains(b.type, "untyped") {
					fmt.wprintf(w, " <span class=\"comment\">// %s</span>", b.type)
				}

				fmt.wprintln(w, "</pre>")
			case "b":
				fmt.wprint(w, `<pre class="doc-code">`)
				fmt.wprintf(w, "%s :: %s", name, b.type)
				io.write_string(w, " {…}")
				fmt.wprintln(w, "</pre>")
			}

			fmt.wprintln(w, `</div>`)

			if len(the_comment) != 0 || len(extra_comment) != 0 {
				fmt.wprintln(w, `<details class="odin-doc-toggle" open>`)
				fmt.wprintln(w, `<summary class="hideme"><span>&nbsp;</span></summary>`)
				write_docs(w, the_comment, name)
				write_docs(w, extra_comment, name)
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
	write_entries(w, runtime_pkg, "Procedures",       "b", runtime_procs[:])
	write_entries(w, runtime_pkg, "Procedure Groups", "g", runtime_groups[:])

	fmt.wprintf(w, `<script type="text/javascript">var odin_pkg_name = "%s";</script>`+"\n", "builtin")
	fmt.wprintln(w, `</section></article>`)

	write_table_contents(w, runtime_pkg, runtime_consts[:], runtime_types[:], runtime_procs[:], runtime_groups[:])

}

@(private)
write_table_contents :: proc(w: io.Writer, runtime_pkg: ^doc.Pkg, consts: []doc.Scope_Entry, types: []doc.Scope_Entry, procs: []doc.Scope_Entry, groups: []doc.Scope_Entry) {
    write_link :: proc(w: io.Writer, id, text: string) {
        fmt.wprintf(w, `<li><a href="#%s">%s</a></li>`, id, text)
        fmt.wprintln(w, "")
    }

    write_table_entries :: proc(w: io.Writer, runetime_pkg: ^doc.Pkg, title: string, kind: string, entries: []doc.Scope_Entry) {
        // if len(entries) == 0 do return
        fmt.wprintln(w, `<li>`)
        {
                fmt.wprintf(w, `<a href="#pkg-{0:s}">{0:s}</a>`, title)
                fmt.wprintln(w, `<ul>`)
                for e in builtins do if e.kind == kind {
                        fmt.wprintf(w, "<li><a href=\"#{0:s}\">{0:s}</a></li>\n", e.name)
                }
                fmt.wprintln(w, `</ul>`)
        }
        fmt.wprintln(w, `</li>`)
    }

    fmt.wprintln(w, `<div class="col-lg-2 odin-toc-border navbar-light"><div class="sticky-top odin-below-navbar py-3">`)
    fmt.wprintln(w, `<nav id="TableOfContents">`)
    fmt.wprintln(w, `<ul>`)

    write_link(w, "pkg-overview", "Overview")

    write_table_entries(w, runtime_pkg, "Constants", "c", consts)
    write_table_entries(w, runtime_pkg, "Types", "t", types)
    write_table_entries(w, runtime_pkg, "Procedures", "b", procs)
    write_table_entries(w, runtime_pkg, "Procedure Groups", "g", groups)
    
    fmt.wprintln(w, `</ul>`)
    fmt.wprintln(w, `</nav>`)
    fmt.wprintln(w, `</div></div>`)
}

intrinsics_entities := []Builtin{
	{name = "is_package_imported", kind = "p", type = "proc(package_name: string) -> bool"},

	{name = "transpose", kind = "p", type = "proc(m: $T/matrix[$R, $C]$E) -> matrix[C, R]E"},
	{name = "outer_product", kind = "p", type = "proc(m: $A/[$X]$E, b: $B/[$Y]E) -> matrix[A, B]E"},
	{name = "hadamard_product", kind = "p", type = "proc(a, b: $T/matrix[$R, $C]$E) -> T"},
	{name = "matrix_flatten", kind = "p", type = "proc(m: $T/matrix[$R, $C]$E) -> [R*E]E"},

	{name = "soa_struct", kind = "p", type = "proc($N: int, $T: typeid) -> type/#soa[N]T"},

	{name = "volatile_load", kind = "p", type = "proc(dst: ^$T) -> T"},
	{name = "volatile_store", kind = "p", type = "proc(dst: ^$T, val: T)"},

	{name = "non_temporal_load", kind = "p", type = "proc(dst: ^$T) -> T"},
	{name = "non_temporal_store", kind = "p", type = "proc(dst: ^$T, val: T)"},

	{name = "debug_trap", kind = "p", type = "proc()"},
	{name = "trap", kind = "p", type = "proc() -> !"},

	{name = "alloca", kind = "p", type = "proc(size, align: int) -> [^]u8"},
	{name = "cpu_relax", kind = "p", type = "proc()"},
	{name = "read_cycle_counter", kind = "p", type = "proc() -> i64"},

	{name = "count_ones", kind = "p", type = "proc(x: $T) -> T"},
	{name = "count_zeros", kind = "p", type = "proc(x: $T) -> T"},
	{name = "count_trailing_zeros", kind = "p", type = "proc(x: $T) -> T"},
	{name = "count_leading_zeros", kind = "p", type = "proc(x: $T) -> T"},
	{name = "reverse_bits", kind = "p", type = "proc(x: $T) -> T"},
	{name = "byte_swap", kind = "p", type = "proc(x: $T) -> T"},

	{name = "overflow_add", kind = "p", type = "proc(lhs, rhs: $T) -> (T, bool)"},
	{name = "overflow_sub", kind = "p", type = "proc(lhs, rhs: $T) -> (T, bool)"},
	{name = "overflow_mul", kind = "p", type = "proc(lhs, rhs: $T) -> (T, bool)"},

	{name = "sqrt", kind = "p", type = "proc(x: $T) -> T"},

	{name = "fused_mul_add", kind = "p", type = "proc(a, b, c: $T) -> T"},

	{name = "mem_copy", kind = "p", type = "proc(dst, src: rawptr, len: int)"},
	{name = "mem_copy_non_overlapping", kind = "p", type = "proc(dst, src: rawptr, len: int)"},
	{name = "mem_zero", kind = "p", type = "proc(ptr: rawptr, len: int)"},
	{name = "mem_zero_volatile", kind = "p", type = "proc(ptr: rawptr, len: int)"},

	{name = "ptr_offset", kind = "p", type = "proc(ptr: ^$T, offset: int) -> ^T", comment = "Prefer [^]T operations if possible."},
	{name = "ptr_sub", kind = "p", type = "proc(a, b: ^$T) -> int", comment = "Prefer [^]T operations if possible."},

	{name = "unaligned_load", kind = "p", type = "proc(src: ^$T) -> T"},
	{name = "unaligned_store", kind = "p", type = "proc(src: ^$T, val: T) -> T"},

	{name = "fixed_point_mul", kind = "p", type = "proc(lhs, rhs: $T, #const scale: uint) -> T"},
	{name = "fixed_point_div", kind = "p", type = "proc(lhs, rhs: $T, #const scale: uint) -> T"},
	{name = "fixed_point_mul_sat", kind = "p", type = "proc(lhs, rhs: $T, #const scale: uint) -> T"},
	{name = "fixed_point_div_sat", kind = "p", type = "proc(lhs, rhs: $T, #const scale: uint) -> T"},

	{name = "prefetch_read_instruction", kind = "p", type = "proc(address: rawptr, #const locality: i32)", comment = "`locality` must be in the range `0..=3`"},
	{name = "prefetch_read_data", kind = "p", type = "proc(address: rawptr, #const locality: i32)", comment = "`locality` must be in the range `0..=3`"},
	{name = "prefetch_write_instruction", kind = "p", type = "proc(address: rawptr, #const locality: i32)", comment = "`locality` must be in the range `0..=3`"},
	{name = "prefetch_write_data", kind = "p", type = "proc(address: rawptr, #const locality: i32)", comment = "`locality` must be in the range `0..=3`"},

	{name = "expect", kind = "p", type = "proc(val, expected_val: T) -> T", comment = "A compiler hint."},

	{name = "syscall", kind = "p", type = "proc(id: uintptr, args: ..uintptr) -> uintptr", comment = "Linux and Darwin only."},

	{name = "Atomic_Memory_Order", kind = "t", value = "Atomic_Memory_Order :: enum {\n\tRelaxed = 0, // Unordered\n\tConsume = 1, // Monotonic\n\tAcquire = 2,\n\tRelease = 3,\n\tAcq_Rel = 4,\n\tSeq_Cst = 5,\n}"},

	{name = "atomic_type_is_lock_free", kind = "p", type = "proc($T: typeid) -> bool"},

	{name = "atomic_thread_fence", kind = "p", type = "proc(order: Atomic_Memory_Order)"},
	{name = "atomic_signal_fence", kind = "p", type = "proc(order: Atomic_Memory_Order)"},

	{name = "atomic_store", kind = "p", type = "proc(dst: ^$T, val: T)"},
	{name = "atomic_store_explicit", kind = "p", type = "proc(dst: ^$T, val: T, order: Atomic_Memory_Order)"},

	{name = "atomic_load", kind = "p", type = "proc(dst: ^$T) -> T"},
	{name = "atomic_load_explicit", kind = "p", type = "proc(dst: ^$T, order: Atomic_Memory_Order) -> T"},

	{name = "atomic_sub", kind = "p", type = "proc(dst: ^$T, val: T) -> T"},
	{name = "atomic_sub_explicit", kind = "p", type = "proc(dst: ^$T, val: T, order: Atomic_Memory_Order) -> T"},

	{name = "atomic_and", kind = "p", type = "proc(dst: ^$T, val: T) -> T"},
	{name = "atomic_and_explicit", kind = "p", type = "proc(dst: ^$T, val: T, order: Atomic_Memory_Order) -> T"},

	{name = "atomic_nand", kind = "p", type = "proc(dst: ^$T, val: T) -> T"},
	{name = "atomic_nand_explicit", kind = "p", type = "proc(dst: ^$T, val: T, order: Atomic_Memory_Order) -> T"},

	{name = "atomic_or", kind = "p", type = "proc(dst: ^$T, val: T) -> T"},
	{name = "atomic_or_explicit", kind = "p", type = "proc(dst: ^$T, val: T, order: Atomic_Memory_Order) -> T"},

	{name = "atomic_xor", kind = "p", type = "proc(dst: ^$T, val: T) -> T"},
	{name = "atomic_xor_explicit", kind = "p", type = "proc(dst: ^$T, val: T, order: Atomic_Memory_Order) -> T"},

	{name = "atomic_exchange", kind = "p", type = "proc(dst: ^$T, val: T) -> T"},
	{name = "atomic_exchange_explicit", kind = "p", type = "proc(dst: ^$T, val: T, order: Atomic_Memory_Order) -> T"},

	{name = "atomic_compare_exchange_strong", kind = "p", type = "proc(dst: ^$T, old, new: T) -> (T, bool)"},
	{name = "atomic_compare_exchange_strong_explicit", kind = "p", type = "proc(dst: ^$T, old, new: T, success, failure: Atomic_Memory_Order) -> (T, bool)"},

	{name = "atomic_compare_exchange_weak", kind = "p", type = "proc(dst: ^$T, old, new: T) -> (T, bool)"},
	{name = "atomic_compare_exchange_weak_explicit", kind = "p", type = "proc(dst: ^$T, old, new: T, success, failure: Atomic_Memory_Order) -> (T, bool)"},

	{name = "type_base_type", kind = "p", type = "proc($T: typeid) -> type"},
	{name = "type_core_type", kind = "p", type = "proc($T: typeid) -> type"},
	{name = "type_elem_type", kind = "p", type = "proc($T: typeid) -> type"},

	{name = "type_is_boolean", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_integer", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_rune", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_float", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_complex", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_quaternion", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_string", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_typeid", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_any", kind = "p", type = "proc($T: typeid) -> bool"},

	{name = "type_is_endian_platform", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_endian_little", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_endian_big", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_unsigned", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_numeric", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_ordered", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_ordered_numeric", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_indexable", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_sliceable", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_comparable", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_simple_compare", kind = "p", type = "proc($T: typeid) -> bool", comment = "Easily compared using memcmp (== and !=)."},
	{name = "type_is_dereferenceable", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_valid_map_key", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_matrix_elements", kind = "p", type = "proc($T: typeid) -> bool"},

	{name = "type_is_named", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_pointer", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_multi_pointer", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_array", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_enumerated_array", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_slice", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_dynamic_array", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_map", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_struct", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_union", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_enum", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_proc", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_bit_set", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_simd_vector", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_matrix", kind = "p", type = "proc($T: typeid) -> bool"},

	{name = "type_has_nil", kind = "p", type = "proc($T: typeid) -> bool"},

	{name = "type_is_specialization_of", kind = "p", type = "proc($T, $S: typeid) -> bool"},

	{name = "type_is_variant_of", kind = "p", type = "proc($U, $V: typeid) -> bool"},
	{name = "type_union_tag_type", kind = "p", type = "proc($T: typeid) -> typeid"},
	{name = "type_union_tag_offset", kind = "p", type = "proc($T: typeid) -> uintptr"},
	{name = "type_union_base_tag_value", kind = "p", type = "proc($T: typeid) -> int"},
	{name = "type_union_variant_count", kind = "p", type = "proc($T: typeid) -> int"},
	{name = "type_variant_type_of", kind = "p", type = "proc($T: typeid, $index: int) -> typeid"},
	{name = "type_variant_index_of", kind = "p", type = "proc($U, $V: typeid) -> int"},

	{name = "type_has_field", kind = "p", type = "proc($T: typeid, $name: string) -> bool"},
	{name = "type_field_type", kind = "p", type = "proc($T: typeid, $name: string) -> typeid"},

	{name = "type_proc_parameter_count", kind = "p", type = "proc($T: typeid) -> int"},
	{name = "type_proc_return_count", kind = "p", type = "proc($T: typeid) -> int"},

	{name = "type_proc_parameter_type", kind = "p", type = "proc($T: typeid, index: int) -> typeid"},
	{name = "type_proc_return_type", kind = "p", type = "proc($T: typeid, index: int) -> typeid"},

	{name = "type_struct_field_count", kind = "p", type = "proc($T: typeid) -> int"},

	{name = "type_polymorphic_record_parameter_count", kind = "p", type = "proc($T: typeid) -> typeid"},
	{name = "type_polymorphic_record_parameter_value", kind = "p", type = "proc($T: typeid, index: int) -> $V"},

	{name = "type_is_specialized_polymorphic_record", kind = "p", type = "proc($T: typeid) -> bool"},
	{name = "type_is_unspecialized_polymorphic_record", kind = "p", type = "proc($T: typeid) -> bool"},

	{name = "type_is_subtype_of", kind = "p", type = "proc($T, $U: typeid) -> bool"},

	{name = "type_field_index_of", kind = "p", type = "proc($T: typeid, $name: string) -> uintptr"},

	{name = "type_equal_proc", kind = "p", type = "proc($T: typeid) -> (equal: proc \"contextless\" (rawptr, rawptr) -> bool)"},
	{name = "type_hasher_proc", kind = "p", type = "proc($T: typeid) -> (hasher: proc \"contextless\" (data: rawptr, seed: rawptr) -> uintptr)"},

	{name = "type_map_info", kind = "p", type = "proc($T: typeid/map[$K]$V) -> ^runtime.Map_Info"},
	{name = "type_map_cell_info", kind = "p", type = "proc($T: typeid) -> ^runtime.Map_Cell_Info"},

	{name = "type_convert_variants_to_pointers", kind = "p", type = "proc($T: typeid) -> typeid"},
	{name = "type_merge", kind = "p", type = "proc($U, $V: typeid) -> typeid"},

	{name = "constant_utf16_cstring", kind = "p", type = "proc($literal: string) -> [^]u16"},

	{name = "simd_add", kind = "p", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},
	{name = "simd_sub", kind = "p", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},
	{name = "simd_mul", kind = "p", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},
	{name = "simd_div", kind = "p", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},

	{name = "simd_shl", kind = "p", type = "proc(a: #simd[N]T, b: #simd[N]Unsigned_Integer) -> #simd[N]T", comment = "Keep Odin's behaviour: `(x << y) if y <= mask else 0`."},
	{name = "simd_shr", kind = "p", type = "proc(a: #simd[N]T, b: #simd[N]Unsigned_Integer) -> #simd[N]T", comment = "Keep Odin's behaviour: `(x << y) if y <= mask else 0`."},

	{name = "simd_shl_masked", kind = "p", type = "proc(a: #simd[N]T, b: #simd[N]Unsigned_Integer) -> #simd[N]T", comment = "Similar to C's behaviour: `x << (y & mask)`."},
	{name = "simd_shr_masked", kind = "p", type = "proc(a: #simd[N]T, b: #simd[N]Unsigned_Integer) -> #simd[N]T", comment = "Similar to C's behaviour: `x << (y & mask)`."},

	{name = "simd_add_sat", kind = "p", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},
	{name = "simd_sub_sat", kind = "p", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},

	{name = "simd_bit_and", kind = "p", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},
	{name = "simd_bit_or", kind = "p", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},
	{name = "simd_bit_xor", kind = "p", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},
	{name = "simd_bit_and_not", kind = "p", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},

	{name = "simd_neg", kind = "p", type = "proc(a: #simd[N]T) -> #simd[N]T"},

	{name = "simd_abs", kind = "p", type = "proc(a: #simd[N]T) -> #simd[N]T"},

	{name = "simd_min", kind = "p", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},
	{name = "simd_max", kind = "p", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},
	{name = "simd_clamp", kind = "p", type = "proc(v, min, max: #simd[N]T) -> #simd[N]T"},

	{name = "simd_lanes_eq", kind = "p", type = "proc(a, b: #simd[N]T) -> #simd[N]Integer", comment = "Returns an unsigned integer of the same size as the input type.\nNOT A BOOLEAN.\nElement-wise:\n\tfalse => 0x00...00\n\ttrue => 0xff...ff"},
	{name = "simd_lanes_ne", kind = "p", type = "proc(a, b: #simd[N]T) -> #simd[N]Integer", comment = "Returns an unsigned integer of the same size as the input type.\nNOT A BOOLEAN.\nElement-wise:\n\tfalse => 0x00...00\n\ttrue => 0xff...ff"},
	{name = "simd_lanes_lt", kind = "p", type = "proc(a, b: #simd[N]T) -> #simd[N]Integer", comment = "Returns an unsigned integer of the same size as the input type.\nNOT A BOOLEAN.\nElement-wise:\n\tfalse => 0x00...00\n\ttrue => 0xff...ff"},
	{name = "simd_lanes_le", kind = "p", type = "proc(a, b: #simd[N]T) -> #simd[N]Integer", comment = "Returns an unsigned integer of the same size as the input type.\nNOT A BOOLEAN.\nElement-wise:\n\tfalse => 0x00...00\n\ttrue => 0xff...ff"},
	{name = "simd_lanes_gt", kind = "p", type = "proc(a, b: #simd[N]T) -> #simd[N]Integer", comment = "Returns an unsigned integer of the same size as the input type.\nNOT A BOOLEAN.\nElement-wise:\n\tfalse => 0x00...00\n\ttrue => 0xff...ff"},
	{name = "simd_lanes_ge", kind = "p", type = "proc(a, b: #simd[N]T) -> #simd[N]Integer", comment = "Returns an unsigned integer of the same size as the input type.\nNOT A BOOLEAN.\nElement-wise:\n\tfalse => 0x00...00\n\ttrue => 0xff...ff"},

	{name = "simd_extract", kind = "p", type = "proc(a: #simd[N]T, idx: uint) -> T"},
	{name = "simd_replace", kind = "p", type = "proc(a: #simd[N]T, idx: uint, elem: T) -> #simd[N]T"},

	{name = "simd_reduce_add_ordered", kind = "p", type = "proc(a: #simd[N]T) -> T"},
	{name = "simd_reduce_mul_ordered", kind = "p", type = "proc(a: #simd[N]T) -> T"},
	{name = "simd_reduce_min", kind = "p", type = "proc(a: #simd[N]T) -> T"},
	{name = "simd_reduce_max", kind = "p", type = "proc(a: #simd[N]T) -> T"},
	{name = "simd_reduce_and", kind = "p", type = "proc(a: #simd[N]T) -> T"},
	{name = "simd_reduce_or", kind = "p", type = "proc(a: #simd[N]T) -> T"},
	{name = "simd_reduce_xor", kind = "p", type = "proc(a: #simd[N]T) -> T"},

	{name = "simd_shuffle", kind = "p", type = "proc(a, b: #simd[N]T, indices: ..int) -> #simd[len(indices)]T"},
	{name = "simd_select", kind = "p", type = "proc(cond: #simd[N]boolean_or_integer, true, false: #simd[N]T) -> #simd[N]T"},

	{name = "simd_ceil", kind = "p", type = "proc(a: #simd[N]any_float) -> #simd[N]any_float"},
	{name = "simd_floor", kind = "p", type = "proc(a: #simd[N]any_float) -> #simd[N]any_float"},
	{name = "simd_trunc", kind = "p", type = "proc(a: #simd[N]any_float) -> #simd[N]any_float"},
	{name = "simd_nearest", kind = "p", type = "proc(a: #simd[N]any_float) -> #simd[N]any_float", comment = "Rounding to the nearest integral value; If two values are equally near, rounds to the even one."},

	{name = "simd_to_bits", kind = "p", type = "proc(v: #simd[N]T) -> #simd[N]Integer"},

	{name = "simd_reverse", kind = "p", type = "proc(a: #simd[N]T) -> #simd[N]T", comment = "Equivalent to a swizzle with descending indices, e.g. `reserve(a, 3, 2, 1, 0)`."},

	{name = "simd_rotate_left", kind = "p", type = "proc(a: #simd[N]T, $offset: int) -> #simd[N]T"},
	{name = "simd_rotate_right", kind = "p", type = "proc(a: #simd[N]T, $offset: int) -> #simd[N]T"},

	{name = "wasm_memory_grow", kind = "p", type = "proc(index, delta: uintptr) -> int"},
	{name = "wasm_memory_size", kind = "p", type = "proc(index: uintptr) -> int"},

	{name = "wasm_memory_atomic_wait32", kind = "p", type = "proc(ptr: ^u32, expected: u32, timeout_ns: i64) -> u32", comment = "`timeout_ns` is maximum number of nanoseconds the calling thread will be blocked for.\nA negative value will be blocked forever.\nReturn value:\n0 - Indicates that the thread blocked and then was woken up.\n1 - The loaded value from `ptr` did not match `expected`, the thread did not block.\n2 - The thread blocked."},
	{name = "wasm_memory_atomic_notify32", kind = "p", type = "proc(ptr: ^u32, waiters: u32) -> (waiters_woken_up: u32)"},

	{name = "x86_cpuid", kind = "p", type = "proc(ax, cx: u32) -> (eax, ebx, ecx, edx: u32)"},
	{name = "x86_xgetbv", kind = "p", type = "proc(cx: u32) -> (eax, edx: u32)"},

	{name = "objc_object", kind = "t", value = "struct{}"},
	{name = "objc_selector", kind = "t", value = "struct{}"},
	{name = "objc_class", kind = "t", value = "struct{}"},
	{name = "objc_id", kind = "t", value = "^objc_object"},
	{name = "objc_SEL", kind = "t", value = "^objc_selector"},
	{name = "objc_Class", kind = "t", value = "^objc_class"},

	{name = "objc_find_selector", kind = "p", type = "proc($name: string) -> objc_SEL"},
	{name = "objc_register_selector", kind = "p", type = "proc($name: string) -> objc_SEL"},
	{name = "objc_find_class", kind = "p", type = "proc($name: string) -> objc_Class"},
	{name = "objc_register_class", kind = "p", type = "proc($name: string) -> objc_Class"},

	{name = "valgrind_client_request", kind = "p", type = "proc(default, request, a0, a1, a2, a3, a4: uintptr) -> uintptr"},

	{name = "__entry_point", kind = "p", type = "proc()", comment = "Internal compiler use only."},
}

intrinsics_docs := `package intrinsics provides documentation for Odin's compiler intrinsics.`

write_intrinsics_pkg :: proc(w: io.Writer, dir, path: string, runtime_pkg: ^doc.Pkg, collection: ^Collection) {
	fmt.wprintln(w, `<div class="row odin-main" id="pkg">`)
	defer fmt.wprintln(w, `</div>`)

	write_pkg_sidebar(w, nil, collection)

	fmt.wprintln(w, `<article class="col-lg-8 p-4 documentation odin-article">`)

	write_breadcrumbs(w, path, runtime_pkg, collection)

	fmt.wprintf(w, "<h1>package %s:%s", strings.to_lower(collection.name, context.temp_allocator), path)

	pkg_src_url := fmt.tprintf("%s/%s", collection.source_url, path)
	fmt.wprintf(w, "<div class=\"doc-source\"><a href=\"{0:s}\"><em>Source</em></a></div>", pkg_src_url)
	fmt.wprintf(w, "</h1>\n")

	write_search(w, .Package)

	fmt.wprintln(w, `<div id="pkg-top">`)

	{
		fmt.wprintln(w, "<h2>Overview</h2>")
		fmt.wprintln(w, "<div id=\"pkg-overview\">")
		defer fmt.wprintln(w, "</div>")

		write_docs(w, intrinsics_docs)
	}

	write_index :: proc(w: io.Writer, name: string, kind: string) {
		entry_count := 0
		for b in intrinsics_entities do if b.kind == kind {
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
			for b in intrinsics_entities do if b.kind == kind {
				fmt.wprintf(w, "<li><a href=\"#{0:s}\">{0:s}</a></li>\n", b.name)
			}

			fmt.wprintln(w, "</ul>")
		}
	}

	fmt.wprintln(w, `<div id="pkg-index">`)
	fmt.wprintln(w, `<h2>Index</h2>`)

	// write_index(w, "Constants",        "c")
	write_index(w, "Types",            "t")
	write_index(w, "Procedures",       "b")
	// write_index(w, "Procedure Groups", "g")

	fmt.wprintln(w, "</div>")
	fmt.wprintln(w, "</div>")

	write_entries :: proc(w: io.Writer, runtime_pkg: ^doc.Pkg, title: string, kind: string) {
		fmt.wprintf(w, "<h2 id=\"pkg-{0:s}\" class=\"pkg-header\">{0:s}</h2>\n", title)
		
		collection := cfg.pkg_to_collection[runtime_pkg]
		runtime_url := fmt.aprintf("%s/%s", collection.base_url, collection.pkg_to_path[runtime_pkg])
		defer delete(runtime_url)

		// intrinsics entries
		for b in intrinsics_entities do if b.kind == kind {
			fmt.wprintln(w, `<div class="pkg-entity">`)
			defer fmt.wprintln(w, `</div>`)

			name := b.name

			fmt.wprintf(w, "<h3 id=\"{0:s}\"><span><a class=\"doc-id-link\" href=\"#{0:s}\">{0:s}", name)
			fmt.wprintf(w, "<span class=\"a-hidden\">&nbsp;¶</span></a></span>")
			fmt.wprintf(w, "</h3>\n")
			fmt.wprintln(w, `<div>`)

			the_comment := b.comment
			extra_comment := ""

			switch b.kind {
			case "c", "t":
				fmt.wprint(w, `<pre class="doc-code">`)
				fmt.wprintf(w, "%s", b.value if len(b.value) != 0 else
				                     "…"     if b.kind == "c"     else
				                     name)
				if strings.contains(b.type, "untyped") {
					fmt.wprintf(w, " <span class=\"comment\">// %s</span>", b.type)
				}

				fmt.wprintln(w, "</pre>")
			case "p":
				fmt.wprint(w, `<pre class="doc-code">`)
				fmt.wprintf(w, "%s :: %s", name, b.type)
				io.write_string(w, " {…}")
				fmt.wprintln(w, "</pre>")
			}

			fmt.wprintln(w, `</div>`)

			if len(the_comment) != 0 || len(extra_comment) != 0 {
				fmt.wprintln(w, `<details class="odin-doc-toggle" open>`)
				fmt.wprintln(w, `<summary class="hideme"><span>&nbsp;</span></summary>`)
				write_docs(w, the_comment, name)
				write_docs(w, extra_comment, name)
				fmt.wprintln(w, `</details>`)
			}
		}
	}

	fmt.wprintln(w, `<section class="documentation">`)
	// write_entries(w, runtime_pkg, "Constants",        "c")
	write_entries(w, runtime_pkg, "Types",            "t")
	write_entries(w, runtime_pkg, "Procedures",       "b")
	// write_entries(w, runtime_pkg, "Procedure Groups", "g")

	fmt.wprintf(w, `<script type="text/javascript">var odin_pkg_name = "%s";</script>`+"\n", "intrinsics")
	fmt.wprintln(w, `</section></article>`)
}
