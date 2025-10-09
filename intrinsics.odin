package odin_html_docs

// Builtin :: struct {
// 	name:    string,
// 	kind:    string,
// 	type:    string,
// 	comment: string,
// 	value:   string,
// }

intrinsics_docs := `package intrinsics provides documentation for Odin's compiler-level intrinsics.`

intrinsics_table := []Builtin{
	// Package Related
	{name = "is_package_imported", kind = "p", type = "proc($package_name: string) -> bool",
		comment = "Returns a constant boolean as to whether or not that package has been imported anywhere in the project. This is only needed for very rare edge cases.",
	},

	// Matrix Related
	{name = "transpose",        kind = "b", type = "proc(m: $M/matrix[$R, $C]$E) -> matrix[C, R]E"},
	{name = "outer_product",    kind = "b", type = "proc(a: $A/[$X]$E, b: $B/[$Y]E) -> matrix[X, Y]E"},
	{name = "hadamard_product", kind = "b", type = "proc(a, b: $T/matrix[$R, $C]$E) -> T"},
	{name = "matrix_flatten",   kind = "b", type = "proc(m: $T/matrix[$R, $C]$E) -> [R*C]E"},

	// Types
	{name = "soa_struct", kind = "b", type = "proc($N: int, $T: typeid) -> type/#soa[N]T",
		comment = "A call-like way to construct an #soa struct. Possibly to be deprecated in the future.",
	},

	// Volatile
	{name = "volatile_load", kind = "b", type = "proc(dst: ^$T) -> T", comment = VOLATILE_COMMENT},
	{name = "volatile_store", kind = "b", type = "proc(dst: ^$T, val: T)", comment = VOLATILE_COMMENT},

	{name = "non_temporal_load", kind = "b", type = "proc(dst: ^$T) -> T", comment = NON_TEMPORAL_COMMENT},
	{name = "non_temporal_store", kind = "b", type = "proc(dst: ^$T, val: T)", comment = NON_TEMPORAL_COMMENT},

	// Trapping
	{name = "debug_trap", kind = "b", type = "proc()", comment = "A call intended to cause an execution trap with the intention of requesting a debugger's attention."},
	{name = "trap", kind = "b", type = "proc() -> !", comment = "Lowered to a target dependent trap instruction."},


	{name = "alloca", kind = "b", type = "proc(size, align: int) -> [^]byte",
		comment = "A procedure that allocates `size` bytes of space in the stack frame of the caller, aligned to `align` bytes. This temporary space is automatically freed when the procedure that called `alloca` returns to its caller.",
	},
	{name = "cpu_relax", kind = "b", type = "proc()",
		comment = "On i386/amd64, it should map to the `pause` instruction. On arm64, it should map to `isb` instruction (see https://bugs.java.com/bugdatabase/view_bug.do?bug_id=8258604 for more information).",
	},
	{name = "read_cycle_counter", kind = "b", type = "proc() -> i64",
		comment = "This provides access to the cycle counter register (or similar low latency, high accuracy clocks) on the targets that support it. On i386/amd64, it should map to the `rdtsc` instruction. On arm64, it should map to the `cntvct_el0` instruction.",
	},
	{name = "read_cycle_counter_frequency", kind = "b", type = "proc() -> i64",
		comment = "This provides access to the frequency that the cycle counter register (or similar low latency, high accuracy clocks) uses on the targets that support it.",
	},

	{name = "count_ones",           kind = "b", type = "proc(x: $T) -> T where type_is_integer(T) || type_is_simd_vector(T)",
		comment = "Counts the number of set bits (`1`s).",
	},
	{name = "count_zeros",          kind = "b", type = "proc(x: $T) -> T where type_is_integer(T) || type_is_simd_vector(T)",
		comment = "Counts the number of unset bits (`0`s).",
	},
	{name = "count_trailing_zeros", kind = "b", type = "proc(x: $T) -> T where type_is_integer(T) || type_is_simd_vector(T)",
		comment = "Counts the number of trailing unset bits (`0`s) until a set bit (`1`) is seen or all bits have been counted.",
	},
	{name = "count_leading_zeros",  kind = "b", type = "proc(x: $T) -> T where type_is_integer(T) || type_is_simd_vector(T)",
		comment = "Counts the number of leading unset bits (`0`s) until a set bit (`1`) is seen or all bits have been counted.",
	},
	{name = "reverse_bits",         kind = "b", type = "proc(x: $T) -> T where type_is_integer(T) || type_is_simd_vector(T)",
		comment = "Reverses the bits from ascending order to descending order e.g. 0b01110101 -> 0b10101110",
	},
	{name = "byte_swap",            kind = "b", type = "proc(x: $T) -> T where type_is_integer(T) || type_is_float(T)",
		comment = "Reverses the bytes from ascending order to descending order e.g. 0xfe_ed_01_12 -> `0x12_01_ed_fe",
	},

	{name = "overflow_add", kind = "b", type = "proc(lhs, rhs: $T) -> (T, bool) where type_is_integer(T) #optional_ok",
		comment = "Performs an \"add\" operation with an overflow check. The second return value will be true if an overflow occurs.",
	},
	{name = "overflow_sub", kind = "b", type = "proc(lhs, rhs: $T) -> (T, bool) where type_is_integer(T) #optional_ok",
		comment = "Performs a \"subtract\" operation with an overflow check. The second return value will be true if an overflow occurs.",
	},
	{name = "overflow_mul", kind = "b", type = "proc(lhs, rhs: $T) -> (T, bool) where type_is_integer(T) #optional_ok",
		comment = "Performs a \"multiply\" operation with an overflow check. The second return value will be true if an overflow occurs.",
	},

	{name = "saturating_add", kind = "b", type = "proc(lhs, rhs: $T) -> T -> where type_is_integer(T)",
		comment = "Performs a saturating \"add\" operation, where the return value is clamped between `min(T)` and `max(T)`.",
	},
	{name = "saturating_sub", kind = "b", type = "proc(lhs, rhs: $T) -> T -> where type_is_integer(T)",
		comment = "Performs a saturating \"subtract\" operation, where the return value is clamped between `min(T)` and `max(T)`.",
	},

	{name = "sqrt", kind = "b", type = "proc(x: $T) -> T where type_is_float(T) || (type_is_simd_vector(T) && type_is_float(type_elem_type(T)))",
		comment = "Returns the square root of a value. If the input value is negative, this is platform defined behaviour.",
	},

	{name = "fused_mul_add", kind = "b", type = "proc(a, b, c: $T) -> T where type_is_float(T) || (type_is_simd_vector(T) && type_is_float(type_elem_type(T)))"},

	{name = "mem_copy",                 kind = "b", type = "proc(dst, src: rawptr, len: int)",
		comment = "Copies a block of memory from the `src` location to the `dst` location but assumes that the memory ranges could be overlapping. It is equivalent to C's `memmove`, but unlike the C's libc procedure, it does not return value.",
	},
	{name = "mem_copy_non_overlapping", kind = "b", type = "proc(dst, src: rawptr, len: int)",
		comment = "Copies a block of memory from the `src` location to the `dst` location but it does not assume the memory ranges could be overlapping. It is equivalent to C's `memcpy`, but unlike the C's libc procedure, it does not return value.",
	},
	{name = "mem_zero",                 kind = "b", type = "proc(ptr: rawptr, len: int)",
		comment = "Zeroes a block of memory at the `ptr` location for `len` bytes.",
	},
	{name = "mem_zero_volatile",        kind = "b", type = "proc(ptr: rawptr, len: int)",
		comment = "Zeroes a block of memory at the `ptr` location for `len` bytes with volatile semantics.",
	},

	// prefer [^]T operations if possible
	{name = "ptr_offset",                 kind = "b", type = "proc(ptr: ^$T, offset: int) -> ^T",
		comment = "Prefer using [^]T operations if possible. e.g. `ptr[offset:]`",
	},
	{name = "ptr_sub",                    kind = "b", type = "proc(a, b: ^$T) -> int",
		comment = "Equivalent to `int(uintptr(a) - uintptr(b)) / size_of(T)`",
	},

	{name = "unaligned_load",             kind = "b", type = "proc(src: ^$T) -> T",
		comment = "Performs a load on an unaligned value `src`.",
	},
	{name = "unaligned_store",            kind = "b", type = "proc(dst: ^$T, val: T) -> T",
		comment = "Performs a store on an unaligned value `dst`.",
	},

	{name = "fixed_point_mul",            kind = "b", type = "proc(lhs, rhs: $T, #const scale: uint) -> T where type_is_integer(T)", comment = FIXED_POINT_COMMENT},
	{name = "fixed_point_div",            kind = "b", type = "proc(lhs, rhs: $T, #const scale: uint) -> T where type_is_integer(T)", comment = FIXED_POINT_COMMENT},
	{name = "fixed_point_mul_sat",        kind = "b", type = "proc(lhs, rhs: $T, #const scale: uint) -> T where type_is_integer(T)", comment = FIXED_POINT_COMMENT},
	{name = "fixed_point_div_sat",        kind = "b", type = "proc(lhs, rhs: $T, #const scale: uint) -> T where type_is_integer(T)", comment = FIXED_POINT_COMMENT},

	{name = "prefetch_read_instruction",  kind = "b", type = "proc(address: rawptr, #const locality: i32 /* 0..=3 */)", comment = PREFETCH_COMMENT},
	{name = "prefetch_read_data",         kind = "b", type = "proc(address: rawptr, #const locality: i32 /* 0..=3 */)", comment = PREFETCH_COMMENT},
	{name = "prefetch_write_instruction", kind = "b", type = "proc(address: rawptr, #const locality: i32 /* 0..=3 */)", comment = PREFETCH_COMMENT},
	{name = "prefetch_write_data",        kind = "b", type = "proc(address: rawptr, #const locality: i32 /* 0..=3 */)", comment = PREFETCH_COMMENT},

	// Compiler Hints
	{name = "expect", kind = "b", type = "proc(val, expected_val: T) -> T",
		comment = "Provides information about expected (the most probable) value of `val`, which can be used by optimizing backends.",
	},

	// Linux and Darwin Only
	{name = "syscall", kind = "b", type = "proc(id: uintptr, args: ..uintptr) -> uintptr", comment="system call for Linux and Darwin Only"},
	// FreeBSD, NetBSD, et cetera
	{name = "syscall_bsd", kind = "b", type = "proc(id: uintptr, args: ..uintptr) -> (uintptr, bool)", comment="system call FreeBSD, NetBSD, etc." },

	// Atomics
	{
		name = "Atomic_Memory_Order", kind = "t",
		type = `enum {
	Relaxed = 0, // Unordered
	Consume = 1, // Monotonic
	Acquire = 2,
	Release = 3,
	Acq_Rel = 4,
	Seq_Cst = 5,
}`,
		comment = "An enumeration of atomic memory orderings used by the `atomic_*_explicit` intrinsics that determines which atomic instructions on the same address they synchronize with."+
		"This follows the same memory model as C11/C++11.",
	},


	{ name = "atomic_type_is_lock_free",                kind = "b", type = "proc($T: typeid) -> bool"},

	{ name = "atomic_thread_fence",                     kind = "b", type = "proc(order: Atomic_Memory_Order)",
		comment = "Adds a \"fence\" to introduce a \"happens-before\" edges between operations.",
	},
	{ name = "atomic_signal_fence",                     kind = "b", type = "proc(order: Atomic_Memory_Order)",
		comment = "Adds a \"fence\" to introduce a \"happens-before\" edges between operations.",
	},

	{ name = "atomic_store",                            kind = "b", type = "proc(dst: ^$T, val: T)"},
	{ name = "atomic_store_explicit",                   kind = "b", type = "proc(dst: ^$T, val: T, order: Atomic_Memory_Order)"},

	{ name = "atomic_load",                             kind = "b", type = "proc(dst: ^$T) -> T"},
	{ name = "atomic_load_explicit",                    kind = "b", type = "proc(dst: ^$T, order: Atomic_Memory_Order) -> T"},

	// fetch then operator
	{ name = "atomic_add",                              kind = "b", type = "proc(dst: ^$T, val: T) -> T"},
	{ name = "atomic_add_explicit",                     kind = "b", type = "proc(dst: ^$T, val: T, order: Atomic_Memory_Order) -> T"},
	{ name = "atomic_sub",                              kind = "b", type = "proc(dst: ^$T, val: T) -> T"},
	{ name = "atomic_sub_explicit",                     kind = "b", type = "proc(dst: ^$T, val: T, order: Atomic_Memory_Order) -> T"},
	{ name = "atomic_and",                              kind = "b", type = "proc(dst: ^$T, val: T) -> T"},
	{ name = "atomic_and_explicit",                     kind = "b", type = "proc(dst: ^$T, val: T, order: Atomic_Memory_Order) -> T"},
	{ name = "atomic_nand",                             kind = "b", type = "proc(dst: ^$T, val: T) -> T"},
	{ name = "atomic_nand_explicit",                    kind = "b", type = "proc(dst: ^$T, val: T, order: Atomic_Memory_Order) -> T"},
	{ name = "atomic_or",                               kind = "b", type = "proc(dst: ^$T, val: T) -> T"},
	{ name = "atomic_or_explicit",                      kind = "b", type = "proc(dst: ^$T, val: T, order: Atomic_Memory_Order) -> T"},
	{ name = "atomic_xor",                              kind = "b", type = "proc(dst: ^$T, val: T) -> T"},
	{ name = "atomic_xor_explicit",                     kind = "b", type = "proc(dst: ^$T, val: T, order: Atomic_Memory_Order) -> T"},
	{ name = "atomic_exchange",                         kind = "b", type = "proc(dst: ^$T, val: T) -> T"},
	{ name = "atomic_exchange_explicit",                kind = "b", type = "proc(dst: ^$T, val: T, order: Atomic_Memory_Order) -> T"},

	{ name = "atomic_compare_exchange_strong",          kind = "b", type = "proc(dst: ^$T, old, new: T) -> (T, bool) #optional_ok"},
	{ name = "atomic_compare_exchange_strong_explicit", kind = "b", type = "proc(dst: ^$T, old, new: T, success, failure: Atomic_Memory_Order) -> (T, bool) #optional_ok"},
	{ name = "atomic_compare_exchange_weak",            kind = "b", type = "proc(dst: ^$T, old, new: T) -> (T, bool) #optional_ok"},
	{ name = "atomic_compare_exchange_weak_explicit",   kind = "b", type = "proc(dst: ^$T, old, new: T, success, failure: Atomic_Memory_Order) -> (T, bool) #optional_ok"},


	// Constant type tests

	{name = "type_base_type",                kind = "b", type = "proc($T: typeid) -> type",
		comment = "Returns the type without any `distinct` indirection e.g. `Foo :: distinct int`, `type_base_type(Foo) == int`",
	},
	{name = "type_core_type",                kind = "b", type = "proc($T: typeid) -> type",
		comment = "Returns the type without any `distinct` indirection and the underlying integer type for an enum or bit_set e.g. `Foo :: distinct int`, `type_core_type(Foo) == int`, or `Bar :: enum u8 {A}`, `type_core_type(Bar) == u8`, or `Baz :: bit_set[Bar; u32]`, `type_core_type(Baz) == u32`",

	},
	{name = "type_elem_type",                kind = "b", type = "proc($T: typeid) -> type",
		comment = "Returns the element type of an compound type.\n\n"+
		"- Complex number: the underlying float type (e.g. `complex64 -> f32`)\n"+
		"- Quaternion: the underlying float type (e.g. `quaternion256 -> f64`)\n"+
		"- Pointer: the base type (e.g. `^T -> T`)\n"+
		"- Array: the element type (e.g. `[N]T -> T`)\n"+
		"- Enumerated Array: the element type (e.g. `[Enum]T -> T`)\n"+
		"- Slice: the element type (e.g. `[]T -> T`)\n"+
		"- Dynamic Array: the element type (e.g. `[dynamic]T -> T`)\n"+
		"",
	},

	{name = "type_is_boolean",               kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Return true if the type is derived from any boolean type: `bool`, `b8`, `b16`, `b32`, `b64`"},
	{name = "type_is_integer",               kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Return true if the type is derived from any integer type"},
	{name = "type_is_rune",                  kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Return true if the type is derived from the `rune` type"},
	{name = "type_is_float",                 kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Return true if the type is derived from any float type"},
	{name = "type_is_complex",               kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Return true if the type is derived from any complex type: `complex32`, `complex64`, `complex128`"},
	{name = "type_is_quaternion",            kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Return true if the type is derived from any quaternion type: `quaternion64`, `quaternion128`, `quaternion256`"},
	{name = "type_is_typeid",                kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Return true if the type is derived from `typeid`"},
	{name = "type_is_any",                   kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Return true if the type is derived from `any`"},
	{name = "type_is_string",                kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Returns true if the type is derived from any string type: `string`, `cstring`, `string16`, `cstring16`"},
	{name = "type_is_string16",                kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Returns true if the type is derived from the `string16` type AND not `cstring16`"},
	{name = "type_is_cstring",                kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Returns true if the type is derived from the `cstring` type"},
	{name = "type_is_cstring16",                kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Returns true if the type is derived from the `cstring16` type"},

	{name = "type_is_endian_platform",       kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Returns true if the type uses the platform native layout rather than a specific layout. Example: `type_is_endian_platform(u32) == true`, `type_is_endian_platform(u32le) == false`, `type_is_endian_platform(u32be) == false`"},
	{name = "type_is_endian_little",         kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Returns true if the type is little endian specific or it is a platform native layout which is also little endian. Example: `type_is_endian_little(u32le) == true`, `type_is_endian_little(u32be) == false`, `type_is_endian_little(u32) == (ODIN_ENDIAN == .Little)`"},
	{name = "type_is_endian_big",            kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Returns true if the type is big endian specific or it is a platform native layout which is also big endian. Example: `type_is_endian_big(u32be) == true`, `type_is_endian_big(u32le) == false`, `type_is_endian_big(u32) == (ODIN_ENDIAN == .Big)`"},
	{name = "type_is_unsigned",              kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Returns true if the type is an unsigned integer or an enum backed by an unsigned integer, and false otherwise for any other type"},
	{name = "type_is_numeric",               kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Returns true if it is a \"numeric\" type in nature:\n\n"+
		"- Any integer\n"+
		"- Any float\n"+
		"- Any complex number\n"+
		"- Any quaternion\n"+
		"- Any enum\n"+
		"- Any fixed-length array of a numeric type\n"+
		"",
	},
	{name = "type_is_ordered",               kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Returns true if the type is an integer, float, rune, any string, pointer, or multi-pointer"},
	{name = "type_is_ordered_numeric",       kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Returns true if the type is an integer, float, or rune"},
	{name = "type_is_indexable",             kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Returns true if a value of this type can indexed:\n\n"+
		"- `string` or `string16`\n"+
		"- Any fixed-length array\n"+
		"- Any slice\n"+
		"- Any dynamic array\n"+
		"- Any map\n"+
		"- Any multi-pointer\n"+
		"- Any enumerated array\n"+
		"- Any matrix\n"+
		"",
	},
	{name = "type_is_sliceable",             kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Returns true if a value of this type can indexed:\n\n"+
		"- `string` or `string16`\n"+
		"- Any fixed-length array\n"+
		"- Any slice\n"+
		"- Any dynamic array\n"+
		"- Any multi-pointer\n"+
		"",
	},
	{name = "type_is_comparable",            kind = "b", type = "proc($T: typeid) -> bool",
		comment = ""+
		"Returns true if the type is comparable, which allows for the use of `==` and `!=` binary operators.\n\n"+
		"One of the following non-compound types (as well as any `distinct` forms): `rune`, `string`, `cstring`, `string16`, `cstring16`, `typeid`, pointer, `#soa` related pointer, multi-pointer, enum, procedure, matrix, `bit_set`, `#simd` vector.\n\n"+
		"One of the following compound types (as well as any `distinct` forms): any array or enumerated array where its element type is also comparable; any `struct` where all of its fields are comparable; any `struct #raw_union` were all of its fields are simply comparable (see `type_is_simple_compare`); any `union` where all of its variants are comparable.\n"+
		"",
	},
	{name = "type_is_simple_compare",        kind = "b", type = "proc($T: typeid) -> bool", comment = "easily compared using memcmp (`==` and `!=`) (not including floats)"},
	{name = "type_is_nearly_simple_compare", kind = "b", type = "proc($T: typeid) -> bool", comment = "easily compared using memcmp (`==` and `!=`) (including floats)"},
	{name = "type_is_dereferenceable",       kind = "b", type = "proc($T: typeid) -> bool", comment = "Must be a pointer type `^T` (not `rawptr`) or an `#soa` related pointer type."},
	{name = "type_is_valid_map_key",         kind = "b", type = "proc($T: typeid) -> bool", comment = "Any comparable type which is not-untyped nor generic."},
	{name = "type_is_valid_matrix_elements", kind = "b", type = "proc($T: typeid) -> bool", comment = "Any integer, float, or complex number type (not-untyped)."},

	{name = "type_is_named",                 kind = "b", type = "proc($T: typeid) -> bool", comment = "Returns true if the type is a named"},
	{name = "type_is_pointer",               kind = "b", type = "proc($T: typeid) -> bool", comment = "Returns true if the base-type is a pointer, i.e. `^T` or `rawptr`"},
	{name = "type_is_multi_pointer",         kind = "b", type = "proc($T: typeid) -> bool", comment = "Returns true if the base-type is a multi pointer, i.e. `[^]T`"},
	{name = "type_is_array",                 kind = "b", type = "proc($T: typeid) -> bool", comment = "Returns true if the base-type is a fixed-length array, i.e. `[N]T`"},
	{name = "type_is_enumerated_array",      kind = "b", type = "proc($T: typeid) -> bool", comment = "Returns true if the base-type is a enumerated array, i.e. `[Some_Enum]T`"},
	{name = "type_is_slice",                 kind = "b", type = "proc($T: typeid) -> bool", comment = "Returns true if the base-type is a slice, i.e. `[]T`"},
	{name = "type_is_dynamic_array",         kind = "b", type = "proc($T: typeid) -> bool", comment = "Returns true if the base-type is a dynamic array, i.e. `[dynamic]T`"},
	{name = "type_is_map",                   kind = "b", type = "proc($T: typeid) -> bool", comment = "Returns true if the base-type is a `map`, i.e. `map[K]V`"},
	{name = "type_is_struct",                kind = "b", type = "proc($T: typeid) -> bool", comment = "Returns true if the base-type is a `struct`"},
	{name = "type_is_union",                 kind = "b", type = "proc($T: typeid) -> bool", comment = "Returns true if the base-type is a `union`, but not `struct #raw_union`"},
	{name = "type_is_enum",                  kind = "b", type = "proc($T: typeid) -> bool", comment = "Returns true if the base-type is a `enum`"},
	{name = "type_is_proc",                  kind = "b", type = "proc($T: typeid) -> bool", comment = "Returns true if the base-type is a `proc`"},
	{name = "type_is_bit_set",               kind = "b", type = "proc($T: typeid) -> bool", comment = "Returns true if the base-type is a `bit_set`"},
	{name = "type_is_simd_vector",           kind = "b", type = "proc($T: typeid) -> bool", comment = "Returns true if the base-type is a simd vector, i.e. `#simd[N]T`"},
	{name = "type_is_matrix",                kind = "b", type = "proc($T: typeid) -> bool", comment = "Returns true if the base-type is a `matrix`"},
	{name = "type_is_raw_union",                kind = "b", type = "proc($T: typeid) -> bool", comment = "Returns true if the base-type is a `struct #raw_union`"},


	{name = "type_has_nil",                             kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Types that support `nil`:\n\n"+
		"- `rawptr`\n"+
		"- `any`\n"+
		"- `cstring`\n"+
		"- `cstring16`\n"+
		"- `typeid`\n"+
		"- `enum`\n"+
		"- `bit_set`\n"+
		"- Slices\n"+
		"- `proc` values\n"+
		"- Pointers\n"+
		"- #soa Pointers\n"+
		"- Multi-Pointers\n"+
		"- Dynamic Arrays\n"+
		"- `map`\n"+
		"- `union` without the `#no_nil` directive\n"+
		"- `#soa` slices\n"+
		"- `#soa` dynamic arrays\n"+
		"",
	},

	{name = "type_is_matrix_row_major",    kind = "b", type = "proc($T: typeid) -> bool where type_is_matrix(T)",
		comment = "Returns true if the type passed is a matrix using `#row_major` ordering, this intrinsic only allows for matrices and will not compile otherwise. Note: The default matrix layout is `#column_major`."},
	{name = "type_is_matrix_column_major", kind = "b", type = "proc($T: typeid) -> bool where type_is_matrix(T)",
		comment = "Returns true if the type passed is a matrix using `#column_major` ordering, this intrinsic only allows for matrices and will not compile otherwise. Note: The default matrix layout is `#column_major`."},

	{name = "type_is_specialization_of",                kind = "b", type = "proc($T, $S: typeid) -> bool",
		comment = "Returns true if the type passed is a specialization of a parametric polymorphic type.\n\n"+
		"Example:\n"+
		"\tFoo :: struct($T: typeid) {x: T}\n"+
		"\tassert(type_is_specialization_of(Foo(int)) == true)\n"+
		"\tassert(type_is_specialization_of(Foo)      == false)\n"+
		"\tassert(type_is_specialization_of(i32)      == false)\n"+
		"",
	},

	{name = "type_is_variant_of",                       kind = "b", type = "proc($U, $V: typeid) -> bool where type_is_union(U)",
		comment = "Returns true if the `V` is a variant of the union type `U`.\n\n"+
		"Example:\n"+
		"\tFoo:: union {i32, f32}\n"+
		"\tassert(type_is_variant_of(Foo, i32)    == true)\n"+
		"\tassert(type_is_variant_of(Foo, f32)    == true)\n"+
		"\tassert(type_is_variant_of(Foo, string) == false)\n"+
		"",
	},
	{name = "type_union_tag_type",                      kind = "b", type = "proc($T: typeid) -> typeid where type_is_union(T)",
		comment = "Returns the type used to store the tag for a union. If no tag is used (e.g. `Maybe(Pointer_Like_Type)`), then `u8` is returned.\n\n"+
		"Possible tag types: `u8`, `u16`, `u32`, `u64`",
	},
	{name = "type_union_tag_offset",                    kind = "b", type = "proc($T: typeid) -> uintptr where type_is_union(T)",
		comment = "Returns the offset to the tag in bytes from the start of the union. If no tag is used (e.g. 'Maybe(Pointer_Like_Type)`), then size of the variant block space is returned.\n\n"+
		"Note: unions store the tag after the variant block space.",
	},
	{name = "type_union_base_tag_value",                kind = "b", type = "proc($T: typeid) -> int where type_is_union(U)",
		comment = "Returns the first valid tag value for the first variant. If `#no_nil` is used, the returned value will be `0`, otherwise `1` will be returned.\n\n"+
		"Example:\n"+
		"\tassert(type_union_base_tag_value(union {i32, f32})         == 1)\n"+
		"\tassert(type_union_base_tag_value(union #no_nil {i32, f32}) == 0)\n"+
		"\tassert(type_union_base_tag_value(Maybe(rawptr})            == 1)\n"+
		"",
	},
	{name = "type_union_variant_count",                 kind = "b", type = "proc($T: typeid) -> int where type_is_union(T)",
		comment = "Returns the number of possible variants a union can be (excluding a possible `nil` state).\n\n"+
		"Example:\n"+
		"\tassert(type_union_variant_count(union {i32, f32})      == 2)\n"+
		"\tassert(type_union_variant_count(union {i32, f32, b32}) == 3)\n"+
		"\tassert(type_union_variant_count(union {})              == 0)\n"+
		"",
	},
	{name = "type_variant_type_of",                     kind = "b", type = "proc($T: typeid, $index: int) -> typeid where type_is_union(T)",
		comment = "Returns the type of a union `T`'s variant at a specified `index`.\n\n"+
		"Example:\n"+
		"\tFoo :: union{i32, f32, string}\n"+
		"\tassert(type_variant_type_of(Foo, 0) == i32)\n"+
		"\tassert(type_variant_type_of(Foo, 1) == f32)\n"+
		"\tassert(type_variant_type_of(Foo, 2) == string)\n"+
		"",
	},
	{name = "type_variant_index_of",                    kind = "b", type = "proc($U, $V: typeid) -> int where type_is_union(U)",
		comment = "Returns the index of a variant `V` of a union `U`.\n\n"+
		"Example:\n"+
		"\tFoo :: union{i32, f32, string}\n"+
		"\tassert(type_variant_type_of(Foo, i32)    == 0)\n"+
		"\tassert(type_variant_type_of(Foo, f32)    == 1)\n"+
		"\tassert(type_variant_type_of(Foo, string) == 2)\n"+
		"",
	},

	{name = "type_bit_set_elem_type",       kind = "b", type = "proc($T: typeid) -> typeid where type_is_bit_set(T)",
		comment = "Returns the element type of a `bit_set` `T`.",
	},
	{name = "type_bit_set_underlying_type", kind = "b", type = "proc($T: typeid) -> typeid where type_is_bit_set(T)",
		comment = "Returns the underlying/backing type of a `bit_set` `T` rather than the element type.\n\n"+
		"Example:\n"+
		"\tassert(type_bit_set_underlying_type(bit_set[0..<8])     == u8)\n"+
		"\tassert(type_bit_set_underlying_type(bit_set[Enum; int]) == int)\n"+
		"",
	},

	{name = "type_has_field",                           kind = "b", type = "proc($T: typeid, $name: string) -> bool",
		comment = "Returns true if the field `name` exists on the type `T`."},
	{name = "type_field_type",                          kind = "b", type = "proc($T: typeid, $name: string) -> typeid",
		comment = "Returns type of the field `name` on the type `T`. Note: the field must exist otherwise this will not compile.",
	},

	{name = "type_proc_parameter_count",                kind = "b", type = "proc($T: typeid) -> int where type_is_proc(T)",
		comment = "Returns the number of parameters a procedure type has.\n\n"+
		"Example:\n"+
		"\tassert(type_proc_parameter_count(proc(i32, f32) -> bool) == 2)\n"+
		"",
	},
	{name = "type_proc_return_count",                   kind = "b", type = "proc($T: typeid) -> int where type_is_proc(T)",
		comment = "Returns the number of return values a procedure type has.\n\n"+
		"Example:\n"+
		"\tassert(type_proc_return_count(proc(i32, f32) -> bool) == 1)\n"+
		"",
	},

	{name = "type_proc_parameter_type",                 kind = "b", type = "proc($T: typeid, index: int) -> typeid where type_is_proc(T)",
		comment = "Returns the type of a parameter of a procedure type at the specified `index`.\n\n"+
		"Example:\n"+
		"\tassert(type_proc_parameter_type(proc(i32, f32) -> bool, 1) == f32)\n"+
		"",
	},
	{name = "type_proc_return_type",                    kind = "b", type = "proc($T: typeid, index: int) -> typeid where type_is_proc(T)",
		comment = "Returns the type of a return value of a procedure type at the specified `index`.\n\n"+
		"Example:\n"+
		"\tassert(type_proc_return_type(proc(i32, f32) -> bool, 0) == bool)\n"+
		"",
	},

	{name = "type_struct_field_count",                  kind = "b", type = "proc($T: typeid) -> int where type_is_struct(T)",
		comment = "Returns the number of fields in a `struct` type.",
	},
	{name = "type_struct_has_implicit_padding",         kind = "b", type = "proc($T: typeid) -> bool where type_is_struct(T)",
		comment = "Returns whether the struct has any implicit padding to ensure correct alignment for the fields.\n\n"+
		"Example:\n"+
		"\tFoo :: struct {x: u8, y: u32}\n"+
		"\tassert(type_struct_has_implicit_padding(Foo) == true)\n"+
		"",
	},

	{name = "type_polymorphic_record_parameter_count",  kind = "b", type = "proc($T: typeid) -> typeid",
		comment = "Returns the number of parametric polymorphic parameters to a parametric polymorphic record type (`struct` or `union`). Fails if the type is not such a type.",
	},
	{name = "type_polymorphic_record_parameter_value",  kind = "b", type = "proc($T: typeid, index: int) -> $V",
		comment = "Returns the value of a specifialized parametric polymorphic record type (`struct` or `union`) at a specified `index`. Fails if the type is not such a type.",
	},

	{name = "type_is_specialized_polymorphic_record",   kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Returns true if the record type (`struct` or `union`) passed is a specialized polymorphic record. Returns false when the type is not polymorphic in the first place."},
	{name = "type_is_unspecialized_polymorphic_record", kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Returns true if the record type (`struct` or `union`) passed is a unspecialized polymorphic record. Returns false when the type is not polymorphic in the first place."},

	{name = "type_is_subtype_of",                       kind = "b", type = "proc($T, $U: typeid) -> bool",
		comment = "Returns true if `T` is a subtype (i.e. `using` was applied on a field) to type `U`."},

	{name = "type_field_index_of",                      kind = "b", type = "proc($T: typeid, $name: string) -> uintptr"},

	{name = "type_equal_proc",                          kind = "b", type = "proc($T: typeid) -> (equal:  proc \"contextless\" (rawptr, rawptr) -> bool)                 where type_is_comparable(T)",
		comment = "Returns the underlying procedure that is used to compare pointers to two values of the same type together. This is used by the `map` type and general complicated comparisons.",
	},
	{name = "type_hasher_proc",                         kind = "b", type = "proc($T: typeid) -> (hasher: proc \"contextless\" (data: rawptr, seed: uintptr) -> uintptr) where type_is_comparable(T)",
		comment = "Returns the underlying procedure that is used to hash a pointer to a value used by the `map` type.",
	},

	{name = "type_map_info",                            kind = "b", type = "proc($T: typeid/map[$K]$V) -> ^runtime.Map_Info"},
	{name = "type_map_cell_info",                       kind = "b", type = "proc($T: typeid) -> ^runtime.Map_Cell_Info"},

	{name = "type_convert_variants_to_pointers",        kind = "b", type = "proc($T: typeid) -> typeid where type_is_union(T)",
		comment = "Returns a type which converts all of the variants of a `union` to be pointer types of those variants.\n\n"+
		"Example:\n"+
		"\tFoo :: union {A, B, C}\n"+
		"\ttype_convert_variants_to_pointers(Foo) == union {^A, ^B, ^C}\n"+
		"",
	},
	{name = "type_merge",                               kind = "b", type = "proc($U, $V: typeid) -> typeid where type_is_union(U), type_is_union(V)",
		comment = "Merges to union's variants into one bigger union.\n\n"+
		"Note: the merging is done is order and duplicate variant types are ignored.\n\n"+
		"Example:\n"+
		"\tA :: union{i32, f32, string}\n"+
		"\tB :: union{bool, complex64}\n"+
		"\tC :: union{string, bool, i32}\n"+
		"\t\n"+
		"\ttype_merge(A, B) == union{i32, f32, string, bool, complex64}\n"+
		"\ttype_merge(A, C) == union{i32, f32, string, bool}\n"+
		"\ttype_merge(B, C) == union{bool, complex64, string, i32}\n"+
		"\ttype_merge(C, A) == union{string, bool, i32, f32}\n"+
		"",
	},

	{name = "constant_utf16_cstring", kind = "b", type = "proc($literal: string) -> [^]u16",
		comment = "Returns a runtime value of a constant string UTF-8 value encoded as a UTF-16 NULL terminated string value, useful for interfacing with UTF-16 procedure such as the Windows API.\n\n"+
		"**Important Note:** This will be deprecated soon as UTF-16 string types and literals are supported natively."+
		"",
	},

	{name = "constant_log2", kind = "b", type = "proc($v: $T) -> T where type_is_integer(T)",
		comment = "Returns the log2 value of the given constant integer.",
	},

	// SIMD related
	{name = "simd_add",                kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},
	{name = "simd_sub",                kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},
	{name = "simd_mul",                kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},
	{name = "simd_div",                kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]T where type_is_float(T)"},

	{name = "simd_saturating_add",     kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]T where type_is_integer(T)"},
	{name = "simd_saturating_sub",     kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]T where type_is_integer(T)"},

	{name = "simd_shl",                kind = "b", type = "proc(a: #simd[N]T, b: #simd[N]Unsigned_Integer) -> #simd[N]T", comment = "Keeps Odin's behaviour: `(x << y) if y <= mask else 0`"},
	{name = "simd_shr",                kind = "b", type = "proc(a: #simd[N]T, b: #simd[N]Unsigned_Integer) -> #simd[N]T", comment = "Keeps Odin's behaviour: `(x >> y) if y <= mask else 0"},

	// Similar to C's Behaviour
	// x << (y & mask)
	{name = "simd_shl_masked",         kind = "b", type = "proc(a: #simd[N]T, b: #simd[N]Unsigned_Integer) -> #simd[N]T", comment = "Similar to C's behaviour: `x << (y & mask)`"},
	{name = "simd_shr_masked",         kind = "b", type = "proc(a: #simd[N]T, b: #simd[N]Unsigned_Integer) -> #simd[N]T", comment = "Similar to C's behaviour: `x >> (y & mask)"},

	{name = "simd_bit_and",            kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},
	{name = "simd_bit_or",             kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},
	{name = "simd_bit_xor",            kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},
	{name = "simd_bit_and_not",        kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},

	{name = "simd_neg",                kind = "b", type = "proc(a: #simd[N]T) -> #simd[N]T"},

	{name = "simd_abs",                kind = "b", type = "proc(a: #simd[N]T) -> #simd[N]T"},

	{name = "simd_min",                kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},
	{name = "simd_max",                kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},
	{name = "simd_clamp",              kind = "b", type = "proc(v, min, max: #simd[N]T) -> #simd[N]T"},

	// Return an unsigned integer of the same size as the input type
	// NOT A BOOLEAN
	// element-wise:
	//     false => 0x00...00
	//     true  => 0xff...ff
	{name = "simd_lanes_eq",           kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]Integer", comment = SIMD_LANES_COMMENT},
	{name = "simd_lanes_ne",           kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]Integer", comment = SIMD_LANES_COMMENT},
	{name = "simd_lanes_lt",           kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]Integer", comment = SIMD_LANES_COMMENT},
	{name = "simd_lanes_le",           kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]Integer", comment = SIMD_LANES_COMMENT},
	{name = "simd_lanes_gt",           kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]Integer", comment = SIMD_LANES_COMMENT},
	{name = "simd_lanes_ge",           kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]Integer", comment = SIMD_LANES_COMMENT},

	{name = "simd_extract",            kind = "b", type = "proc(a: #simd[N]T, idx: uint) -> T", comment = "Extracts a single scalar element from a `#simd` vector at a specified index."},
	{name = "simd_replace",            kind = "b", type = "proc(a: #simd[N]T, idx: uint, elem: T) -> #simd[N]T", comment = "Replaces a single scalar element from a `#simd` vector and returns a new vector."},

	{name = "simd_reduce_add_ordered", kind = "b", type = "proc(a: #simd[N]T) -> T", comment = SIMD_REDUCE_PREFIX + "simd_reduce_add_ordered" + SIMD_REDUCE_MID + "result = result + e"     + SIMD_REDUCE_SUFFIX},
	{name = "simd_reduce_mul_ordered", kind = "b", type = "proc(a: #simd[N]T) -> T", comment = SIMD_REDUCE_PREFIX + "simd_reduce_mul_ordered" + SIMD_REDUCE_MID + "result = result * e"     + SIMD_REDUCE_SUFFIX},
	{name = "simd_reduce_min",         kind = "b", type = "proc(a: #simd[N]T) -> T", comment = SIMD_REDUCE_PREFIX + "simd_reduce_min"         + SIMD_REDUCE_MID + "result = min(result, e)" + SIMD_REDUCE_SUFFIX},
	{name = "simd_reduce_max",         kind = "b", type = "proc(a: #simd[N]T) -> T", comment = SIMD_REDUCE_PREFIX + "simd_reduce_max"         + SIMD_REDUCE_MID + "result = max(result, e)" + SIMD_REDUCE_SUFFIX},
	{name = "simd_reduce_and",         kind = "b", type = "proc(a: #simd[N]T) -> T", comment = SIMD_REDUCE_PREFIX + "simd_reduce_and"         + SIMD_REDUCE_MID + "result = result & e"     + SIMD_REDUCE_SUFFIX},
	{name = "simd_reduce_or",          kind = "b", type = "proc(a: #simd[N]T) -> T", comment = SIMD_REDUCE_PREFIX + "simd_reduce_or"          + SIMD_REDUCE_MID + "result = result | e"     + SIMD_REDUCE_SUFFIX},
	{name = "simd_reduce_xor",         kind = "b", type = "proc(a: #simd[N]T) -> T", comment = SIMD_REDUCE_PREFIX + "simd_reduce_xor"         + SIMD_REDUCE_MID + "result = result ~ e"     + SIMD_REDUCE_SUFFIX},

	{name = "simd_reduce_any",         kind = "b", type = "proc(a: #simd[N]T) -> T where type_is_boolean(T)" },
	{name = "simd_reduce_all",         kind = "b", type = "proc(a: #simd[N]T) -> T where type_is_boolean(T)" },

	{name = "simd_extract_msbs",       kind = "b", type = "proc(a: #simd[N]T) -> bit_set[0..<N] where type_is_integer(T) || type_is_boolean(T)",
		comment = "Extracts the most significant bit of each element of the given vector into a `bit_set`.",
	},
	{name = "simd_extract_lsbs",       kind = "b", type = "proc(a: #simd[N]T) -> bit_set[0..<N] where type_is_integer(T) || type_is_boolean(T)",
		comment = "Extracts the least significant bit of each element of the given vector into a `bit_set`.",
	},

	{name = "simd_gather",             kind = "b", type = "proc(ptr: #simd[N]rawptr, val: #simd[N]T, mask: #simd[N]U) -> #simd[N]T where type_is_integer(U) || type_is_boolean(U)"},
	{name = "simd_scatter",            kind = "b", type = "proc(ptr: rawptr, val: #simd[N]T, mask: #simd[N]U) where type_is_integer(U) || type_is_boolean(U)"},

	{name = "simd_masked_load",        kind = "b", type = "proc(ptr: rawptr, val: #simd[N]T, mask: #simd[N]U) -> #simd[N]T where type_is_integer(U) || type_is_boolean(U)"},
	{name = "simd_masked_store",       kind = "b", type = "proc(ptr: rawptr, val: #simd[N]T, mask: #simd[N]U) where type_is_integer(U) || type_is_boolean(U)"},

	{name = "simd_masked_expand_load",    kind = "b", type = "proc(ptr: rawptr, val: #simd[N]T, mask: #simd[N]U) -> #simd[N]T where type_is_integer(U) || type_is_boolean(U)"},
	{name = "simd_masked_compress_store", kind = "b", type = "proc(ptr: rawptr, val: #simd[N]T, mask: #simd[N]U) where type_is_integer(U) || type_is_boolean(U)"},

	{name = "simd_shuffle",            kind = "b", type = "proc(a, b: #simd[N]T, $indices: ..int) -> #simd[len(indices)]T",
		comment =
		"The first two operators of `simd_shuffle` are `#simd` vectors of the same type. The indices following these represent the shuffle mask values. The mask elements must be constant integers. The result of the procedure is a vector whose length is the same as the number of indices passed to the procedure type.\n\n"+
		"The elements of the two input `#simd` vectors are numbers from left to right across both of the vectors. For each element of the result `#simd` vector, the shuffle indices selement an element from one of the two input vectors to copy to the result.\n\n"+
		"Example:\n"+
		"\ta, b: #simd[4]T = ...\n"+
		"\tx: #simd[4]T = intrinsics.simd_shuffle(a, b, 0, 1, 2, 3) // identity shuffle of `a`\n"+
		"\ty: #simd[4]T = intrinsics.simd_shuffle(a, b, 4, 5, 6, 7) // identity shuffle of `b`\n"+
		"\tz: #simd[4]T = intrinsics.simd_shuffle(a, b, 0, 4, 1, 5)\n"+
		"\tw: #simd[8]T = intrinsics.simd_shuffle(a, b, 0, 1, 2, 3, 4, 5, 6, 7)\n"+
		"\tv: #simd[6]T = intrinsics.simd_shuffle(a, b, 0, 1, 0, 3, 0, 4) // repeated indices and different sized vector\n"+
		"",
	},
	{name = "simd_select",             kind = "b", type = "proc(cond: #simd[N]boolean_or_integer, true, false: #simd[N]T) -> #simd[N]T"},

	// Lane-wise operations
	{name = "simd_ceil",               kind = "b", type = "proc(a: #simd[N]any_float) -> #simd[N]any_float", comment = "lane-wise ceil"},
	{name = "simd_floor",              kind = "b", type = "proc(a: #simd[N]any_float) -> #simd[N]any_float", comment = "lane-wise floor"},
	{name = "simd_trunc",              kind = "b", type = "proc(a: #simd[N]any_float) -> #simd[N]any_float", comment = "lane-wise trunc"},

	{name = "simd_nearest",            kind = "b", type = "proc(a: #simd[N]any_float) -> #simd[N]any_float", comment = "rounding to the nearest integral value; if two values are equally near, rounds to the even one"},

	{name = "simd_to_bits",            kind = "b", type = "proc(v: #simd[N]T) -> #simd[N]Integer where size_of(T) == size_of(Integer), type_is_unsigned(Integer)"},

	{name = "simd_lanes_reverse",      kind = "b", type = "proc(a: #simd[N]T) -> #simd[N]T", comment = "equivalent a swizzle with descending indices, e.g. reserve(a, 3, 2, 1, 0)"},

	{name = "simd_lanes_rotate_left",  kind = "b", type = "proc(a: #simd[N]T, $offset: int) -> #simd[N]T"},
	{name = "simd_lanes_rotate_right", kind = "b", type = "proc(a: #simd[N]T, $offset: int) -> #simd[N]T"},

	{name = "has_target_feature", kind = "b", type = "proc($test: $T) -> bool where type_is_string(T) || type_is_proc(T)",
		comment =
		"Checks if the current target supports the given target features.\n\n" +
		"Takes a constant comma-separated string (eg: \"sha512,sse4.1\"), or a procedure type which has either " +
		"`@(require_target_feature)` or `@(enable_target_feature)` as its input and returns a boolean indicating " +
		"if all listed features are supported.",
	},

	{name = "procedure_of", kind = "b", type = "proc(x: $T) -> T where type_is_proc(T)", comment = "Returns the value of the procedure where `x` must be a call expression." },

	// WASM targets only
	{name = "wasm_memory_grow", kind = "b", type = "proc(index, delta: uintptr) -> int", comment = "WASM targets only"},
	{name = "wasm_memory_size", kind = "b", type = "proc(index: uintptr) -> int", comment = "WASM targets only"},

	{name = "wasm_memory_atomic_wait32",   kind = "b", type ="proc(ptr: ^u32, expected: u32, timeout_ns: i64) -> u32",
		comment = "Blocks the calling thread for a given duration if the value pointed to by `ptr` is equal to the value of `expected`.\n"+
		"`timeout_ns` is the maximum number of nanoseconds the calling thread will be blocked for.  If `timeout_ns` is negative, the calling thread will be blocked forever.\n"+
		"Returns:\n"+
		"- `0`: the thread blocked and then was woken up\n"+
		"- `1`: the loaded value from `ptr` did not match `expected`, the thread did not block\n"+
		"- `2`: the thread blocked, but the timeout expired\n"+
		"",
	},
	{name = "wasm_memory_atomic_notify32", kind = "b", type ="proc(ptr: ^u32, waiters: u32) -> (waiters_woken_up: u32)",
		comment = "Wakes threads waiting on the address indicated by `ptr`, up to the given maximum (`waiters`). If `waiters` is zero, no threads are woken up. Threads previously blocked with `wasm_memory_atomic_wait32` will be woken up.\n"+
		"Returns:\n"+
		"The number of threads woken up.\n",
	},

	// x86 Targets (i386, amd64)
	{name = "x86_cpuid",  kind = "b", type = "proc(ax, cx: u32) -> (eax, ebx, ecx, edx: u32)", comment = X86_COMMENT + "\nImplements the `cpuid` instruction."},
	{name = "x86_xgetbv", kind = "b", type = "proc(cx: u32) -> (eax, edx: u32)", comment = X86_COMMENT+"\nImplements in `xgetbv` instruction."},

	// Darwin targets only
	{name = "objc_object",            kind = "t", type="struct {}",                             comment = DARWIN_COMMENT + "\nRepresents an Objective-C `object` type."},
	{name = "objc_selector",          kind = "t", type="struct {}",                             comment = DARWIN_COMMENT + "\nRepresents an Objective-C `selector` type."},
	{name = "objc_class",             kind = "t", type="struct {}",                             comment = DARWIN_COMMENT + "\nRepresents an Objective-C `class` type."},
	{name = "objc_id",                kind = "t", type="^objc_object",                          comment = DARWIN_COMMENT + "\nRepresents an Objective-C `id` type."},
	{name = "objc_SEL",               kind = "t", type="^objc_selector",                        comment = DARWIN_COMMENT + "\nRepresents an Objective-C `SEL` type."},
	{name = "objc_Class",             kind = "t", type="^objc_class",                           comment = DARWIN_COMMENT + "\nRepresents an Objective-C `Class` type."},

	{name = "objc_find_selector",     kind = "b", type="proc($name: string) -> objc_SEL", comment = DARWIN_COMMENT + "\nWill return a run-time cached selector value for the given constant string value."},
	{name = "objc_register_selector", kind = "b", type="proc($name: string) -> objc_SEL", comment = DARWIN_COMMENT + "\nWill register a selector value at run-time for the given constant string value."},
	{name = "objc_find_class",        kind = "b", type="proc($name: string) -> objc_Class", comment = DARWIN_COMMENT + "\nWill return a run-time cached class value for the given constant string value."},
	{name = "objc_register_class",    kind = "b", type="proc($name: string) -> objc_Class", comment = DARWIN_COMMENT + "\nWill register a class value at run-time for the given constant string value."},

	{name = "valgrind_client_request", kind = "b", type = "proc(default: uintptr, request: uintptr, a0, a1, a2, a3, a4: uintptr) -> uintptr" },
}



SIMD_LANES_COMMENT :: "Return an unsigned integer of the same size as the input type, NOT A BOOLEAN. element-wise: `false => 0x00...00`, `true => 0xff...ff`"

X86_COMMENT :: "x86 Targets Only (i386, amd64)"
DARWIN_COMMENT :: "Darwin targets only"

FIXED_POINT_COMMENT :: "A fixed point number represents a real data type for a number that has a fixed number of digits after a radix point. The number of digits after the radix point is referred to as `scale`."


SIMD_REDUCE_PREFIX :: "Performs a reduction of a `#simd` vector `a`, returning the result as a scalar. The return type matches the element-type `T` of the `#simd` vector input. See the following pseudocode:\n\t"
SIMD_REDUCE_MID :: " :: proc(v: #simd[N]T) -> T {\n"+
	"\t\tresult := simd_extract(v, 0)\n"+
	"\t\tfor i in 1..<N {\n"+
	"\t\t\te := simd_extract(v, i)\n"+
	"\t\t\t"

SIMD_REDUCE_SUFFIX :: "\n"+
	"\t\t}\n"+
	"\t\treturn result\n"+
	"\t}"

PREFETCH_COMMENT :: ""+
	"The `prefetch_*` intrinsic are a hint to the code generator to insert a prefetch instruction if supported; otherwise, it is a no-op. Prefetches have no affect on the behaviour of the program but can change its performance characteristics.\n\n"+
	"The `locality` parameter must be a constant integer, and its temporal locality value ranges from `0` (no locality) to `3` (extremely local, keep in cache)."



VOLATILE_COMMENT :: ""+
	"Tells the optimizing backend of a compiler to not change the number of 'volatile' operations nor change their order of execution relative to other 'volatile' operations. "+
	"Optimizers are allowed to change the order of volatile operations relative to non-volatile operations.\n\n"+
	"Note: This has nothing to do with Java's 'volatile' and has no cross-thread synchronization behaviour. Use atomics if this behaviour is wanted."

NON_TEMPORAL_COMMENT :: ""+
	"Tells the code generator of a compiler that this operation is not expected to be reused in the cache. The code generator may select special instructions to save cache bandwidth (e.g. on x86, `movnt` instruct might be used)."
