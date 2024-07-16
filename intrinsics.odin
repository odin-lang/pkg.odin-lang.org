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

	// Types
	{name = "soa_struct", kind = "b", type = "proc($N: int, $T: typeid) -> type/#soa[N]T",
		comment = "A call-like way to construct an #soa struct. Possibly to be deprecated in the future.",
	},

	// Volatile
	{name = "volatile_load", kind = "b", type = "proc(dst: ^$T) -> T", comment = VOLATILE_COMMENT},
	{name = "volatile_store", kind = "b", type = "proc(dst: ^$T, val: T)", comment = VOLATILE_COMMENT},

	{name = "non_temporal_load", kind = "b", type = "proc(dst: ^$T) -> T", comment = NON_TEMPORAL_COMMENT},
	{name = "non_temporal_store", kind = "b", type = "proc(dst: ^$T, val: T)", comment = NON_TEMPORAL_COMMENT},


	{name = "debug_trap", kind = "b", type = "proc()", comment = "A call intended to cause an execution trap with the intention of requesting a debugger's attention."},
	{name = "trap", kind = "b", type = "proc() -> !", comment = "Lowered to a target dependent trap instruction."},


	{name = "alloca", kind = "b", type = "proc(size, align: int) -> [^]u8",
		comment = "A procedure that allocates `size` bytes of space in the stack frame of the caller, aligned to `align` bytes. This temporary space is automatically freed when the procedure that called `alloca` returns to its caller.",
	},
	{name = "cpu_relax", kind = "b", type = "proc()",
		comment = "On i386/amd64, it should map to the `pause` instruction. On arm64, it should map to `isb` instruction (see https://bugs.java.com/bugdatabase/view_bug.do?bug_id=8258604 for more information).",
	},
	{name = "read_cycle_counter", kind = "b", type = "proc() -> i64",
		comment = "This provides access to the cycle counter register (or similar low latency, high accuracy clocks) on the targets that support it. On i386/amd64, it should map to the `rdtsc` instruction. On arm64, it should map to the `cntvct_el0` instruction.",
	},

	{name = "count_ones",           kind = "b", type = "proc(x: $T) -> T where type_is_integer(T) || type_is_simd_vector(T)",
		comment = "Counts the number of set bits (`1`s).",
	},
	{name = "count_zeros",          kind = "b", type = "proc(x: $T) -> T where type_is_integer(T) || type_is_simd_vector(T)",
		comment = "Counts the number of unset bits (`0`s).",
	},
	{name = "count_trailing_zeros", kind = "b", type = "proc(x: $T) -> T where type_is_integer(T) || type_is_simd_vector(T)",
		comment = "Counts the number of trailing unset bits (`0`s) until a set bit (`1`)` is seen or if at all.",
	},
	{name = "count_leading_zeros",  kind = "b", type = "proc(x: $T) -> T where type_is_integer(T) || type_is_simd_vector(T)",
		comment = "Counts the number of leading unset bits (`0`s) until a set bit (`1`)` is seen or if at all.",
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
		comment = "Performs an \"multiply\" operation with an overflow check. The second return value will be true if an overflow occurs.",
	},
	{name = "overflow_mul", kind = "b", type = "proc(lhs, rhs: $T) -> (T, bool) where type_is_integer(T) #optional_ok",
		comment = "Performs an \"subtract\" operation with an overflow check. The second return value will be true if an overflow occurs.",
	},

	{name = "add_sat", kind = "b", type = "proc(lhs, rhs: $T) -> T -> where type_is_integer(T)",
		comment = "Performs a saturating \"add\" operation, where the return value is clamped between `min(T)` and `max(T)`.",
	},
	{name = "sub_sat", kind = "b", type = "proc(lhs, rhs: $T) -> T -> where type_is_integer(T)",
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

	{name = "constant_utf16_cstring", kind = "b", type = "proc($literal: string) -> [^]u16",
		comment = "Returns a run-time value of a constant string UTF-8 value encoded as a UTF-16 NUL terminated string value, useful for interfacing with UTF-16 procedure such as the Windows API.",
	},

	// Matrix Related

	{name = "transpose",        kind = "b", type = "proc(m: $M/matrix[$R, $C]$E) -> matrix[C, R]E"},
	{name = "outer_product",    kind = "b", type = "proc(a: $A/[$I]$E, b: $B/[$J]E) -> (c: [I*J]E)"},
	{name = "hadamard_product", kind = "b", type = "proc(a, b: $M/matrix[$R, $C]$E) -> (c: M)"},
	{name = "matrix_flatten",   kind = "b", type = "proc(m: $M/matrix[$R, $C]$E) -> [R*C]E"},

	// Compiler Hints
	{name = "expect", kind = "b", type = "proc(val, expected_val: T) -> T",
		comment = "Provides information about expected (the most probable) value of `val`, which can be used by optimizing backends.",
	},

	// Linux and Darwin Only
	{name = "syscall", kind = "b", type = "proc(id: uintptr, args: ..uintptr) -> uintptr", comment="Linux and Darwin Only"},

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
		comment = "Returns the type without any `distinct` indirection and the underlying integer type for an enum e.g. `Foo :: distinct int`, `type_core_type(Foo) == int`, or `Bar :: enum u8 {A}`, `type_core_type(Bar) == u8`",

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

	{name = "type_is_boolean",               kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_integer",               kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_rune",                  kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_float",                 kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_complex",               kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_quaternion",            kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_string",                kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_typeid",                kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_any",                   kind = "b", type = "proc($T: typeid) -> bool"},

	{name = "type_is_endian_platform",       kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_endian_little",         kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_endian_big",            kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_unsigned",              kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Returns true if a \"numeric\" in nature:\n\n"+
		"- Any integer\n"+
		"- Any float\n"+
		"- Any complex number\n"+
		"- Any quaternion\n"+
		"- Any enum\n"+
		"- Any fixed-array of a numeric type\n"+
		"",
	},
	{name = "type_is_numeric",               kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_ordered",               kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_ordered_numeric",       kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_indexable",             kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_sliceable",             kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_comparable",            kind = "b", type = "proc($T: typeid) -> bool",
		comment = ""+
		"Returns true if the type is comparable, which allows for the use of `==` and `!=` binary operators.\n\n"+
		"One of the following non-compound types (as well as any `distinct` forms): `rune`, `string`, `cstring`, `typeid`, pointer, `#soa` related pointer, multi-pointer, enum, procedure, matrix, `bit_set`, `#simd` vector.\n\n"+
		"One of the following compound types (as well as any `distinct` forms): any array or enumerated array where its element type is also comparable; any `struct` where all of its fields are comparable; any `struct #raw_union` were all of its fields are simply comparable (see `type_is_simple_compare`); any `union` where all of its variants are comparable.\n"+
		"",
	},
	{name = "type_is_simple_compare",        kind = "b", type = "proc($T: typeid) -> bool", comment = "easily compared using memcmp (== and !=)"},
	{name = "type_is_dereferenceable",       kind = "b", type = "proc($T: typeid) -> bool", comment = "Must be a pointer type `^T` (not `rawptr`) or an `#soa` related pointer type."},
	{name = "type_is_valid_map_key",         kind = "b", type = "proc($T: typeid) -> bool", comment = "Any comparable type which is not-untyped nor generic."},
	{name = "type_is_valid_matrix_elements", kind = "b", type = "proc($T: typeid) -> bool", comment = "Any integer, float, or complex number type (not-untyped)."},

	{name = "type_is_named",                 kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_pointer",               kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_multi_pointer",         kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_array",                 kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_enumerated_array",      kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_slice",                 kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_dynamic_array",         kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_map",                   kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_struct",                kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_union",                 kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_enum",                  kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_proc",                  kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_bit_set",               kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_simd_vector",           kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_matrix",                kind = "b", type = "proc($T: typeid) -> bool"},


	{name = "type_has_nil",                             kind = "b", type = "proc($T: typeid) -> bool",
		comment = "Types that support `nil`:\n\n"+
		"- `rawptr`\n"+
		"- `any`\n"+
		"- `cstring`\n"+
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

	{name = "type_is_specialization_of",                kind = "b", type = "proc($T, $S: typeid) -> bool"},

	{name = "type_is_variant_of",                       kind = "b", type = "proc($U, $V: typeid) -> bool where type_is_union(U)"},
	{name = "type_union_tag_type",                      kind = "b", type = "proc($T: typeid) -> typeid where type_is_union(T)"},
	{name = "type_union_tag_offset",                    kind = "b", type = "proc($T: typeid) -> uintptr where type_is_union(T)"},
	{name = "type_union_base_tag_value",                kind = "b", type = "proc($T: typeid) -> int where type_is_union(U)"},
	{name = "type_union_variant_count",                 kind = "b", type = "proc($T: typeid) -> int where type_is_union(T)"},
	{name = "type_variant_type_of",                     kind = "b", type = "proc($T: typeid, $index: int) -> typeid where type_is_union(T)"},
	{name = "type_variant_index_of",                    kind = "b", type = "proc($U, $V: typeid) -> int where type_is_union(U)"},

	{name = "type_has_field",                           kind = "b", type = "proc($T: typeid, $name: string) -> bool"},
	{name = "type_field_type",                          kind = "b", type = "proc($T: typeid, $name: string) -> typeid"},

	{name = "type_proc_parameter_count",                kind = "b", type = "proc($T: typeid) -> int where type_is_proc(T)"},
	{name = "type_proc_return_count",                   kind = "b", type = "proc($T: typeid) -> int where type_is_proc(T)"},

	{name = "type_proc_parameter_type",                 kind = "b", type = "proc($T: typeid, index: int) -> typeid where type_is_proc(T)"},
	{name = "type_proc_return_type",                    kind = "b", type = "proc($T: typeid, index: int) -> typeid where type_is_proc(T)"},

	{name = "type_struct_field_count",                  kind = "b", type = "proc($T: typeid) -> int where type_is_struct(T)"},

	{name = "type_polymorphic_record_parameter_count",  kind = "b", type = "proc($T: typeid) -> typeid"},
	{name = "type_polymorphic_record_parameter_value",  kind = "b", type = "proc($T: typeid, index: int) -> $V"},

	{name = "type_is_specialized_polymorphic_record",   kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_unspecialized_polymorphic_record", kind = "b", type = "proc($T: typeid) -> bool"},

	{name = "type_is_subtype_of",                       kind = "b", type = "proc($T, $U: typeid) -> bool"},

	{name = "type_field_index_of",                      kind = "b", type = "proc($T: typeid, $name: string) -> uintptr"},

	{name = "type_equal_proc",                          kind = "b", type = "proc($T: typeid) -> (equal:  proc \"contextless\" (rawptr, rawptr) -> bool)                 where type_is_comparable(T)",
		comment = "Returns the underlying procedure that is used to compare pointers to two values of the same time together. This is used by the `map` type and general complicated comparisons.",
	},
	{name = "type_hasher_proc",                         kind = "b", type = "proc($T: typeid) -> (hasher: proc \"contextless\" (data: rawptr, seed: uintptr) -> uintptr) where type_is_comparable(T)",
		comment = "Returns the underlying procedure that is used to hash a pointer to a value used by the `map` type.",
	},

	{name = "type_map_info",                            kind = "b", type = "proc($T: typeid/map[$K]$V) -> ^runtime.Map_Info"},
	{name = "type_map_cell_info",                       kind = "b", type = "proc($T: typeid) -> ^runtime.Map_Cell_Info"},

	{name = "type_convert_variants_to_pointers",        kind = "b", type = "proc($T: typeid) -> typeid where type_is_union(T)",
		comment = "Returns a type which converts all of the variants of a `union` to be pointer types of those variants.\n\n"+
		"Example:\n"+
		"	Foo :: union {A, B, C}\n"+
		"	type_convert_variants_to_pointers(Foo) == union {^A, ^B, ^C}\n"+
		"",
	},
	{name = "type_merge",                               kind = "b", type = "proc($U, $V: typeid) -> typeid where type_is_union(U), type_is_union(V)"},




	// SIMD related
	{name = "simd_add",                kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},
	{name = "simd_sub",                kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},
	{name = "simd_mul",                kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},
	{name = "simd_div",                kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]T where type_is_float(T)"},

	{name = "simd_shl",                kind = "b", type = "proc(a: #simd[N]T, b: #simd[N]Unsigned_Integer) -> #simd[N]T", comment = "Keeps Odin's behaviour: `(x << y) if y <= mask else 0`"},
	{name = "simd_shr",                kind = "b", type = "proc(a: #simd[N]T, b: #simd[N]Unsigned_Integer) -> #simd[N]T", comment = "Keeps Odin's behaviour: `(x >> y) if y <= mask else 0"},

	// Similar to C's Behaviour
	// x << (y & mask)
	{name = "simd_shl_masked",         kind = "b", type = "proc(a: #simd[N]T, b: #simd[N]Unsigned_Integer) -> #simd[N]T", comment = "Similar to C's behaviour: `x << (y & mask)`"},
	{name = "simd_shr_masked",         kind = "b", type = "proc(a: #simd[N]T, b: #simd[N]Unsigned_Integer) -> #simd[N]T", comment = "Similar to C's behaviour: `x >> (y & mask)"},

	{name = "simd_add_sat",            kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},
	{name = "simd_sub_sat",            kind = "b", type = "proc(a, b: #simd[N]T) -> #simd[N]T"},

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

	{name = "simd_reverse",            kind = "b", type = "proc(a: #simd[N]T) -> #simd[N]T", comment = "equivalent a swizzle with descending indices, e.g. reserve(a, 3, 2, 1, 0)"},

	{name = "simd_rotate_left",        kind = "b", type = "proc(a: #simd[N]T, $offset: int) -> #simd[N]T"},
	{name = "simd_rotate_right",       kind = "b", type = "proc(a: #simd[N]T, $offset: int) -> #simd[N]T"},




	// WASM targets only
	{name = "wasm_memory_grow", kind = "b", type = "proc(index, delta: uintptr) -> int", comment = "WASM targets only"},
	{name = "wasm_memory_size", kind = "b", type = "proc(index: uintptr) -> int", comment = "WASM targets only"},

	{name = "wasm_memory_atomic_wait32",   kind = "b", type ="proc(ptr: ^u32, expected: u32, timeout_ns: i64) -> u32", comment = WASM_ATOMIC_COMMENT},
	{name = "wasm_memory_atomic_notify32", kind = "b", type ="proc(ptr: ^u32, waiters: u32) -> (waiters_woken_up: u32)", comment = WASM_ATOMIC_COMMENT},

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
}



SIMD_LANES_COMMENT :: "Return an unsigned integer of the same size as the input type, NOT A BOOLEAN. element-wise: `false => 0x00...00`, `true => 0xff...ff`"


WASM_ATOMIC_COMMENT :: "`timeout_ns` is maximum number of nanoseconds the calling thread will be blocked for\n"+
"A negative value will be blocked forever\n"+
"Return value:\n"+
"0 - indicates that the thread blocked and then was woken up\n"+
"1 - the loaded value from `ptr` did not match `expected`, the thread did not block\n"+
"2 - the thread blocked, but the timeout\n"+
""

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
	"The `prefetch_read_instruction` intrinsic is a hint to the code gnerator to insert a prefetch instruction if supported; otherwise, it is a no-op. Prefetches have no affect on the behaviour of the program but can change its performance characteristics.\n\n"+
	"The `locality` parameter must be a constant integer, and its temporal locality value ranges from `0` (no locality) to `3` (extremely local, keep in cache)."



VOLATILE_COMMENT :: ""+
	"Tells the optimizing backend of a compiler to not change the number of 'volatile' operations nor change their order of execution relative to other 'volatile' operations. "+
	"Optimizers are allowed to change the order of volatile operations relative to non-volatile operations.\n\n"+
	"NOTE: This has nothing to do with Java's 'volatile' and has no cross-thread synchronization behaviour. Use atomics if this behaviour is wanted."

NON_TEMPORAL_COMMENT :: ""+
	"Tells the code generator of a compiler that this operation is not expected to be reused in the cache. The code generator may select special instructions to save cache bandwidth (e.g. on x86, `movnt` instruct might be used)."
