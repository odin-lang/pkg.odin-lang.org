package odin_html_docs

import "core:fmt"
import "core:io"
import "core:slice"
import "core:strings"
import "core:text/scanner"
import "core:unicode"

import doc "core:odin/doc-format"

Builtin :: struct {
	name:    string,
	kind:    string,
	type:    string,
	comment: string,
	value:   string,
}

builtin_docs := `package builtin provides documentation for Odin's predeclared identifiers. The items documented here are not actually in package builtin but here to allow for better documentation for the language's special identifiers.`

builtins := []Builtin{
	{name = "nil",          kind = "c", type = "untyped nil", comment = "`nil` is a predeclared identifier representing the zero value for a pointer, multi-pointer, enum, bit_set, slice, dynamic array, map, procedure, any, typeid, cstring, union, #soa array, #soa pointer, #relative type"},
	{name = "false",        kind = "c", type = "untyped boolean", value = "0 != 0"},
	{name = "true",         kind = "c", type = "untyped boolean", value = "0 == 0"},

	{name = "ODIN_OS",      kind = "c", type = "runtime.Odin_OS_Type",     comment = "An enum value specifying the target platform's operating system."},
	{name = "ODIN_ARCH",    kind = "c", type = "runtime.Odin_Arch_Type",   comment = "An enum value specifying the target platform's architecture."},
	{name = "ODIN_ENDIAN",  kind = "c", type = "runtime.Odin_Endian_Type", comment = "An enum value specifying the target platform's endiannes."},
	{name = "ODIN_BUILD_MODE",  kind = "c", type = "runtime.Odin_Build_Mode_Type", comment = "An enum value specifying the \"build-mode\"."},
	{name = "ODIN_ERROR_POS_STYLE",  kind = "c", type = "runtime.Odin_Error_Pos_Style_Type",
		comment = "An enum value specifying whether errors should be stylized in the default (MSVC-like) style or a UNIX (GCC-like) style.\n\n"+
		"- Default = `path(1:2)\n"+
		"- Unix = `path:1:2:\n"+
		"",
	},
	{name = "ODIN_PLATFORM_SUBTARGET",  kind = "c", type = "runtime.Odin_Platform_Subtarget_Type", comment = "An enum value specifying the selected subtarget type, only useful for Darwin targets."},
	{name = "ODIN_WINDOWS_SUBSYSTEM",  kind = "c", type = "untyped string", comment = "A string specifying the current Windows subsystem, only useful on Windows targets."},


	{name = "ODIN_VENDOR",  kind = "c", type = "untyped string",           comment = "A string specifying the current Odin compiler vendor."},
	{name = "ODIN_VERSION", kind = "c", type = "untyped string",           comment = "A string specifying the current Odin version."},
	{name = "ODIN_ROOT",    kind = "c", type = "untyped string",           comment = "The path to the root Odin directory."},
	{name = "ODIN_DEBUG",   kind = "c", type = "untyped boolean",          comment = "Equal to `true` if the `-debug` flag has been set during compilation, otherwise `false`."},
	{name = "ODIN_DISABLE_ASSERT", kind = "c", type = "untyped boolean", comment = "Equal to `true` if the `-disable-assert` flag has been set during compilation, otherwise `false`."},
	{name = "ODIN_DEFAULT_TO_NIL_ALLOCATOR", kind = "c", type = "untyped boolean", comment = "Equal to `true` if the `-default-to-nil-allocator` flag has been set during compilation or whether the current target defaults to the \"nil allocator\", otherwise `false`."},
	{name = "ODIN_DEFAULT_TO_PANIC_ALLOCATOR", kind = "c", type = "untyped boolean", comment = "Equal to `true` if the `-default-to-panic-allocator` flag has been set during compilation or whether the current target defaults to the \"panic allocator\", otherwise `false`."},
	{name = "ODIN_NO_CRT", kind = "c", type = "untyped boolean", comment = "Equal to `true` if the `-no-crt` flag has been set during compilation (disallowing the C Run-Time library), otherwise `false`."},
	{name = "ODIN_NO_ENTRY_POINT", kind = "c", type = "untyped boolean", comment = "Equal to `true` if the `-no-entry-point` flag has been set during compilation, otherwise `false`."},
	{name = "ODIN_NO_RTTI", kind = "c", type = "untyped boolean", comment = "Equal to `true` if the `-no-rtti` flag has been set during compilation (disabling Odin's Run-Time Type Information, only allowed on freestanding targets), otherwise `false`."},
	{name = "ODIN_COMPILE_TIMESTAMP", kind = "c", type = "untyped integer", comment = "Equal to the UNIX timestamp in nanoseconds at the time of the program's compilation."},


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
	{name = "cstring", kind = "t", comment = "`cstring` is the set of all strings of 8-bit bytes terminated with a NUL (0) byte, conventionally but not necessarily representing UTF-8 encoding text. A `cstring` may be empty or `nil`. Elements of `cstring` type are immutable but not indexable."},

	{name = "string16",  kind = "t", comment = "`string16` is the set of all strings of 16-bit code units, conventionally but not necessarily representing UTF-16 encoding text. A `string` may be empty but not `nil`. Elements of `string` type are immutable and indexable."},
	{name = "cstring16", kind = "t", comment = "`cstring16` is the set of all strings of 16-bit code units terminated with a NUL (0) code unit, conventionally but not necessarily representing UTF-16 encoding text. A `cstring16` may be empty or `nil`. Elements of `cstring16` type are immutable but not indexable."},


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
	{name = "kmag",       kind = "b", type = "proc(v: Quaternion) -> Float",            comment = "`kmag` returns the k-imaginary part of a quaternion number `v`. The return value will be the floating-point type corresponding to the type of `v`."},
	{name = "conj",       kind = "b", type = "proc(v: Complex_Or_Quaternion) -> Complex_Or_Quaternion", comment = "`conj` returns the complex conjugate of a complex or quaternion number `v`. This negates the imaginary component(s) whilst keeping the real component untouched."},

	{name = "expand_values", kind = "b", type = "proc(value: Struct_Or_Array) -> (A, B, C, ...)", comment = "`expand_values` will return multiple values corresponding to the multiple fields of the passed struct or the multiple elements of a passed fixed length array."},

	{name = "min",       kind = "b", type = "proc(values: ..T) -> T",
		comment = "`min` returns the minimum value of passed arguments of all the same type.\n" +
		          "If one argument is passed and it is an enum or numeric type, then `min` returns the minimum value of the enum type's fields or its minimum / most negative numeric value respectively.",
	},
	{name = "max",       kind = "b", type = "proc(values: ..T) -> T",
		comment = "`max` returns the maximum value of passed arguments of all the same type.\n" +
		          "If one argument is passed and it is an enum or numeric type, then `max` returns the maximum value of the enum type's fields or its maximum numeric value respectively.",
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

add_styling_to_builtin :: proc(txt: string) -> string {
	s := scanner.init(&{}, txt)
	s.flags -= {.Skip_Comments}
	s.is_ident_rune = proc(ch: rune, i: int) -> bool {
		if i == 0 {
			if ch == '#' {
				return true
			}
			if unicode.is_digit(ch) {
				return false
			}
		}
		return ch == '_' || unicode.is_letter(ch) || unicode.is_digit(ch)
	}

	b: [dynamic]byte
	b.allocator = context.temp_allocator
	prev_offset := 0


	loop: for {
		append_span :: proc(b: ^[dynamic]byte, s: ^scanner.Scanner, class: string, text: string, prev_offset: ^int) {
			append(b, s.src[prev_offset^:s.tok_pos])
			append(b, `<span class="`)
			append(b, class)
			append(b, `">`)
			append(b, text)
			append(b, `</span>`)
			prev_offset^ = s.tok_end
		}
		append_anchored_span :: proc(b: ^[dynamic]byte, s: ^scanner.Scanner, anchor: string, class: string, text: string, prev_offset: ^int) {
			append(b, s.src[prev_offset^:s.tok_pos])
			append(b, `<a href="`)
			append(b, anchor)
			append(b, `#`)
			append(b, text)
			append(b, `">`)
			append(b, `<span class="`)
			append(b, class)
			append(b, `">`)
			append(b, text)
			append(b, `</span></a>`)
			prev_offset^ = s.tok_end
		}
		append_anchored_span_other :: proc(b: ^[dynamic]byte, s: ^scanner.Scanner, anchor: string, class: string, text: string, prev_offset: ^int) {
			append(b, s.src[prev_offset^:s.tok_pos])
			append(b, `<a href="`)
			append(b, anchor)
			append(b, `">`)
			append(b, `<span class="`)
			append(b, class)
			append(b, `">`)
			append(b, text)
			append(b, `</span></a>`)
			prev_offset^ = s.tok_end
		}


		switch scanner.scan(s) {
		case scanner.EOF:
			break loop
		case scanner.Int, scanner.Float:
			number := scanner.token_text(s)
			append_span(&b, s, "number", number, &prev_offset)
		case scanner.Ident:
			ident := scanner.token_text(s)
			found := false
			if !found do for iname in intrinsics_table {
				if iname.name == ident {
					append_anchored_span(&b, s, "/base/intrinsics", "code-procedure", ident, &prev_offset)
					found = true
					break
				}
			}

			if !found do for bname in builtins {
				if bname.name == ident {
					append_anchored_span(&b, s, "/base/builtin", "code-procedure", ident, &prev_offset)
					found = true
					break
				}
			}

			if !found {
				switch ident {
				case "runtime":
					if scanner.peek(s) == '.' {
						_ = scanner.scan(s)

						assert(scanner.scan(s) == scanner.Ident)
						code_ident := scanner.token_text(s)

						append_anchored_span(&b, s, "/base/runtime", "code-typename", code_ident, &prev_offset)
					}

				case "where", "distinct":
					append_span(&b, s, "keyword", ident, &prev_offset)
					prev_offset = s.tok_end
				case "proc", "enum", "struct", "union", "map", "typeid", "matrix", "dynamic":
					append_span(&b, s, "keyword-type", ident, &prev_offset)

				case "#soa":
					append_anchored_span_other(&b, s, "//odin-lang.org/docs/overview/#soa-data-types", "directive", ident, &prev_offset)
				case "#optional_ok":
					append_anchored_span_other(&b, s, "//odin-lang.org/docs/overview/#optional_ok", "directive", ident, &prev_offset)

				case "#simd", "#const":
					append_span(&b, s, "directive", ident, &prev_offset)

				case "Atomic_Memory_Order",
				     "objc_object", "objc_selector", "objc_class",
				     "objc_id", "objc_SEL", "objc_Class":
					append_anchored_span(&b, s, "/base/intrinsics", "code-typename", ident, &prev_offset)

				case "uintptr", "uint", "int",
				     "u128", "i128",
				     "u64",  "i64",
				     "u32",  "i32",
				     "u16",  "i16",
				     "u8",
				     "bool",
				     "string", "cstring",
				     "string16", "cstring16",
				     "rawptr":
					append_anchored_span(&b, s, "/base/builtin", "doc-builtin", ident, &prev_offset)
				}
			}
		case scanner.Comment:
			comment := scanner.token_text(s)
			append_span(&b, s, "comment", comment, &prev_offset)
		}
	}

	if len(b) != 0 {
		append(&b, s.src[prev_offset:])

		return string(b[:])
	}

	return txt
}


write_butilin_entry :: proc(w: io.Writer, runtime_pkg: ^doc.Pkg, runtime_url: string, b: Builtin, kind: string) {
	if b.kind != kind {
		return
	}

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

		if len(b.type) != 0 && b.kind == "t" {
			io.write_string(w, add_styling_to_builtin(b.type))
		} else if len(b.value) != 0 && b.kind == "t" {
			io.write_string(w, add_styling_to_builtin(b.value))
		} else {
			fmt.wprintf(w, "%s", b.value if len(b.value) != 0 else
			                     "…"     if b.kind == "c"     else
			                     name)
		}
		if strings.contains(b.type, "untyped") {
			fmt.wprintf(w, " <span class=\"comment\">// %s</span>", b.type)
		}

		fmt.wprintln(w, "</pre>")
	case "b":
		fmt.wprint(w, `<pre class="doc-code">`)
		fmt.wprintf(w, "%s :: %s", name, add_styling_to_builtin(b.type))
		io.write_string(w, " {…}")
		fmt.wprintln(w, "</pre>")
	}

	fmt.wprintln(w, `</div>`)

	core_comment := ""


	// NOTE(bill): This gets the comments from the `core:simd` package, to minimize documentation duplication
	simd_docs: if strings.has_prefix(name, "simd_") {
		simd_name := name[len("simd_"):]

		core     := (&cfg._collections["core"]) or_break simd_docs
		simd_pkg := core.pkgs["simd"]           or_break simd_docs
		for e in array(simd_pkg.entries) {
			if str(e.name) == simd_name {
				simd_entity := &cfg.entities[e.entity]
				core_comment = str(simd_entity.docs)
				core_comment = strings.trim_space(core_comment)
				break
			}
		}
	}

	// NOTE(bill): This gets the comments from the `core:sync` package, to minimize documentation duplication
	atomic_docs: if strings.has_prefix(name, "atomic_") || strings.has_prefix(name, "Atomic_") {
		atomic_name := name

		core     := (&cfg._collections["core"]) or_break atomic_docs
		sync_pkg := core.pkgs["sync"]           or_break atomic_docs
		for e in array(sync_pkg.entries) {
			if str(e.name) == atomic_name {
				atomic_entity := &cfg.entities[e.entity]
				core_comment = str(atomic_entity.docs)
				core_comment = strings.trim_space(core_comment)
				break
			}
		}
	}


	if core_comment == "" || the_comment == "" || extra_comment == "" {
		fmt.wprintln(w, `<details class="odin-doc-toggle" open>`)
		fmt.wprintln(w, `<summary class="hideme"><span>&nbsp;</span></summary>`)
		if the_comment != "" {
			write_docs(w, the_comment, name)
		}
		if extra_comment != "" {
			write_docs(w, extra_comment, name)
		}
		if core_comment != "" {
			write_docs(w, core_comment, name)
		}
		fmt.wprintln(w, `</details>`)
	}
}

write_builtin_pkg :: proc(w: io.Writer, dir, path: string, runtime_pkg: ^doc.Pkg, collection: ^Collection, pkg_name: string, pkg_docs: string) {
	slice.sort_by(builtins, proc(a, b: Builtin) -> bool {
		if a.kind == b.kind {
			return a.name < b.name
		}
		return a.kind < b.kind
	})
	slice.sort_by(intrinsics_table, proc(a, b: Builtin) -> bool {
		if a.kind == b.kind {
			return a.name < b.name
		}
		return a.kind < b.kind
	})

	fmt.wprintln(w, `<div class="row odin-main" id="pkg">`)
	defer fmt.wprintln(w, `</div>`)

	write_pkg_sidebar(w, nil, collection, pkg_name, path)

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

		write_docs(w, pkg_docs)
	}

	write_index :: proc(w: io.Writer, runtime_entries: []doc.Scope_Entry, name: string, kind: string, builtin_entities: ^[dynamic]doc.Scope_Entry, pkg_name: string, entry_table: []Builtin) {
		entry_count := 0

		if pkg_name == "builtin" {
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
		}

		any_builtin := entry_count > 0

		for b in entry_table do if b.kind == kind {
			entry_count += 1
		}

		slice.sort_by_key(builtin_entities^[:], entity_key)

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
			for b in entry_table do if b.kind == kind {
				fmt.wprintf(w, "<li><a href=\"#{0:s}\">{0:s}</a></li>\n", b.name)
			}

			if any_builtin {
				for entry in builtin_entities {
					e := &cfg.entities[entry.entity]
					fmt.wprintf(w, "<li><a href=\"/base/runtime\">runtime</a>.<a href=\"#{0:s}\">{0:s}</a></li>\n", str(e.name))
				}
			}

			fmt.wprintln(w, "</ul>")
		}
	}

	fmt.wprintln(w, `<div id="pkg-index">`)
	fmt.wprintln(w, `<h2>Index</h2>`)

	entry_table := builtins
	if pkg_name == "intrinsics" {
		entry_table = intrinsics_table
	}

	runtime_entries := slice.clone(array(runtime_pkg.entries))
	defer delete(runtime_entries)
	slice.sort_by_key(runtime_entries, entity_key)

	runtime_consts: [dynamic]doc.Scope_Entry
	runtime_types:  [dynamic]doc.Scope_Entry
	runtime_procs:  [dynamic]doc.Scope_Entry
	runtime_groups: [dynamic]doc.Scope_Entry
	defer delete(runtime_consts)
	defer delete(runtime_types)
	defer delete(runtime_procs)
	defer delete(runtime_groups)

	write_index(w, runtime_entries, "Constants",        "c", &runtime_consts, pkg_name, entry_table)
	write_index(w, runtime_entries, "Types",            "t", &runtime_types,  pkg_name, entry_table)
	write_index(w, runtime_entries, "Procedures",       "b", &runtime_procs,  pkg_name, entry_table)
	write_index(w, runtime_entries, "Procedure Groups", "g", &runtime_groups, pkg_name, entry_table)

	fmt.wprintln(w, "</div>")
	fmt.wprintln(w, "</div>")


	write_entries :: proc(w: io.Writer, runtime_pkg: ^doc.Pkg, title: string, kind: string, entries: []doc.Scope_Entry, entry_table: []Builtin) {
		fmt.wprintf(w, "<h2 id=\"pkg-{0:s}\" class=\"pkg-header\">{0:s}</h2>\n", title)
		
		collection := cfg.pkg_to_collection[runtime_pkg]
		runtime_url := fmt.aprintf("%s/%s", collection.base_url, collection.pkg_to_path[runtime_pkg])
		defer delete(runtime_url)

		// builtin entries
		for b in entry_table {
			write_butilin_entry(w, runtime_pkg, runtime_url, b, kind)
		}

		// @builtin package runtime entries
		for e in entries {
			fmt.wprintln(w, `<div class="pkg-entity">`)
			write_entry(w, runtime_pkg, e)
			fmt.wprintln(w, `</div>`)
		}
	}


	fmt.wprintln(w, `<section class="documentation">`)
	write_entries(w, runtime_pkg, "Constants",        "c", runtime_consts[:], entry_table)
	write_entries(w, runtime_pkg, "Types",            "t", runtime_types[:],  entry_table)
	write_entries(w, runtime_pkg, "Procedures",       "b", runtime_procs[:],  entry_table)
	write_entries(w, runtime_pkg, "Procedure Groups", "g", runtime_groups[:], entry_table)

	fmt.wprintf(w, `<script type="text/javascript">var odin_pkg_name = "%s";</script>`+"\n", pkg_name)
	fmt.wprintln(w, `</section></article>`)

	write_table_contents(w, runtime_pkg, runtime_consts[:], runtime_types[:], runtime_procs[:], runtime_groups[:], entry_table)

}

@(private)
write_table_contents :: proc(w: io.Writer, runtime_pkg: ^doc.Pkg, consts: []doc.Scope_Entry, types: []doc.Scope_Entry, procs: []doc.Scope_Entry, groups: []doc.Scope_Entry, entry_table: []Builtin) {
	write_link :: proc(w: io.Writer, id, text: string) {
		fmt.wprintf(w, `<li><a href="#%s">%s</a></li>`, id, text)
		fmt.wprintln(w, "")
	}

	write_table_entries :: proc(w: io.Writer, runetime_pkg: ^doc.Pkg, title: string, kind: string, entries: []doc.Scope_Entry, entry_table: []Builtin) {
		// if len(entries) == 0 do return
		fmt.wprintln(w, `<li>`)
		{
			fmt.wprintf(w, `<a href="#pkg-{0:s}">{0:s}</a>`, title)
			fmt.wprintln(w, `<ul>`)
			for e in entry_table do if e.kind == kind {
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

	write_table_entries(w, runtime_pkg, "Constants", "c", consts, entry_table)
	write_table_entries(w, runtime_pkg, "Types", "t", types, entry_table)
	write_table_entries(w, runtime_pkg, "Procedures", "b", procs, entry_table)
	write_table_entries(w, runtime_pkg, "Procedure Groups", "g", groups, entry_table)

	fmt.wprintln(w, `</ul>`)
	fmt.wprintln(w, `</nav>`)
	fmt.wprintln(w, `</div></div>`)
}
