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
	{name = "is_package_imported", kind = "p", type = "proc($package_name: string) -> bool", comment = ""},

	// Types
	{name = "soa_struct", kind = "b", type = "proc($N: int, $T: typeid) -> type/#soa[N]T", comment = ""},

	// Volatile
	{name = "volatile_load", kind = "b", type = "proc(dst: ^$T) -> T"},
	{name = "volatile_store", kind = "b", type = "proc(dst: ^$T, val: T)"},

	{name = "non_temporal_load", kind = "b", type = "proc(dst: ^$T) -> T"},
	{name = "non_temporal_store", kind = "b", type = "proc(dst: ^$T, val: T)"},


	{name = "debug_trap", kind = "b", type = "proc()"},
	{name = "trap", kind = "b", type = "proc() -> !"},


	{name = "alloca", kind = "b", type = "proc(size, align: int) -> [^]u8"},
	{name = "cpu_relax", kind = "b", type = "proc()"},
	{name = "read_cycle_counter", kind = "b", type = "proc() -> i64"},

	{name = "count_ones",           kind = "b", type = "proc(x: $T) -> T where type_is_integer(T) || type_is_simd_vector(T)"},
	{name = "count_zeros",          kind = "b", type = "proc(x: $T) -> T where type_is_integer(T) || type_is_simd_vector(T)"},
	{name = "count_trailing_zeros", kind = "b", type = "proc(x: $T) -> T where type_is_integer(T) || type_is_simd_vector(T)"},
	{name = "count_leading_zeros",  kind = "b", type = "proc(x: $T) -> T where type_is_integer(T) || type_is_simd_vector(T)"},
	{name = "reverse_bits",         kind = "b", type = "proc(x: $T) -> T where type_is_integer(T) || type_is_simd_vector(T)"},
	{name = "byte_swap",            kind = "b", type = "proc(x: $T) -> T where type_is_integer(T) || type_is_float(T)"},

	{name = "overflow_add", kind = "b", type = "proc(lhs, rhs: $T) -> (T, bool) #optional_ok"},
	{name = "overflow_sub", kind = "b", type = "proc(lhs, rhs: $T) -> (T, bool) #optional_ok"},
	{name = "overflow_mul", kind = "b", type = "proc(lhs, rhs: $T) -> (T, bool) #optional_ok"},

	{name = "sqrt", kind = "b", type = "proc(x: $T) -> T where type_is_float(T) || (type_is_simd_vector(T) && type_is_float(type_elem_type(T)))"},

	{name = "fused_mul_add", kind = "b", type = "proc(a, b, c: $T) -> T where type_is_float(T) || (type_is_simd_vector(T) && type_is_float(type_elem_type(T)))"},

	{name = "mem_copy",                 kind = "b", type = "proc(dst, src: rawptr, len: int)"},
	{name = "mem_copy_non_overlapping", kind = "b", type = "proc(dst, src: rawptr, len: int)"},
	{name = "mem_zero",                 kind = "b", type = "proc(ptr: rawptr, len: int)"},
	{name = "mem_zero_volatile",        kind = "b", type = "proc(ptr: rawptr, len: int)"},

	// prefer [^]T operations if possible
	{name = "ptr_offset",                 kind = "b", type = "proc(ptr: ^$T, offset: int) -> ^T"},
	{name = "ptr_sub",                    kind = "b", type = "proc(a, b: ^$T) -> int"},

	{name = "unaligned_load",             kind = "b", type = "proc(src: ^$T) -> T"},
	{name = "unaligned_store",            kind = "b", type = "proc(dst: ^$T, val: T) -> T"},

	{name = "fixed_point_mul",            kind = "b", type = "proc(lhs, rhs: $T, #const scale: uint) -> T where type_is_integer(T)"},
	{name = "fixed_point_div",            kind = "b", type = "proc(lhs, rhs: $T, #const scale: uint) -> T where type_is_integer(T)"},
	{name = "fixed_point_mul_sat",        kind = "b", type = "proc(lhs, rhs: $T, #const scale: uint) -> T where type_is_integer(T)"},
	{name = "fixed_point_div_sat",        kind = "b", type = "proc(lhs, rhs: $T, #const scale: uint) -> T where type_is_integer(T)"},

	{name = "prefetch_read_instruction",  kind = "b", type = "proc(address: rawptr, #const locality: i32 /* 0..=3 */)"},
	{name = "prefetch_read_data",         kind = "b", type = "proc(address: rawptr, #const locality: i32 /* 0..=3 */)"},
	{name = "prefetch_write_instruction", kind = "b", type = "proc(address: rawptr, #const locality: i32 /* 0..=3 */)"},
	{name = "prefetch_write_data",        kind = "b", type = "proc(address: rawptr, #const locality: i32 /* 0..=3 */)"},

	{name = "constant_utf16_cstring", kind = "b", type = "proc($literal: string) -> [^]u16"},

	// Matrix Related

	{name = "transpose",        kind = "b", type = "proc(m: $M/matrix[$R, $C]$E) -> matrix[C, R]E"},
	{name = "outer_product",    kind = "b", type = "proc(a: $A/[$I]$E, b: $B/[$J]E) -> (c: [I*J]E)"},
	{name = "hadamard_product", kind = "b", type = "proc(a, b: $M/matrix[$R, $C]$E) -> (c: M)"},
	{name = "matrix_flatten",   kind = "b", type = "proc(m: $M/matrix[$R, $C]$E) -> [R*C]E"},

	// Compiler Hints
	{name = "expect", kind = "b", type = "proc(val, expected_val: T) -> T", comment="Compiler Hint"},

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
	},


	{ name = "atomic_type_is_lock_free",                kind = "b", type = "proc($T: typeid) -> bool"},

	{ name = "atomic_thread_fence",                     kind = "b", type = "proc(order: Atomic_Memory_Order)"},
	{ name = "atomic_signal_fence",                     kind = "b", type = "proc(order: Atomic_Memory_Order)"},

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

	{name = "type_base_type",                kind = "b", type = "proc($T: typeid) -> type"},
	{name = "type_core_type",                kind = "b", type = "proc($T: typeid) -> type"},
	{name = "type_elem_type",                kind = "b", type = "proc($T: typeid) -> type"},

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
	{name = "type_is_unsigned",              kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_numeric",               kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_ordered",               kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_ordered_numeric",       kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_indexable",             kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_sliceable",             kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_comparable",            kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_simple_compare",        kind = "b", type = "proc($T: typeid) -> bool", comment = "easily compared using memcmp (== and !=)"},
	{name = "type_is_dereferenceable",       kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_valid_map_key",         kind = "b", type = "proc($T: typeid) -> bool"},
	{name = "type_is_valid_matrix_elements", kind = "b", type = "proc($T: typeid) -> bool"},

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


	{name = "type_has_nil",                             kind = "b", type = "proc($T: typeid) -> bool"},

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

	{name = "type_equal_proc",                          kind = "b", type = "proc($T: typeid) -> (equal:  proc \"contextless\" (rawptr, rawptr) -> bool)                 where type_is_comparable(T)"},
	{name = "type_hasher_proc",                         kind = "b", type = "proc($T: typeid) -> (hasher: proc \"contextless\" (data: rawptr, seed: uintptr) -> uintptr) where type_is_comparable(T)"},

	{name = "type_map_info",                            kind = "b", type = "proc($T: typeid/map[$K]$V) -> ^runtime.Map_Info"},
	{name = "type_map_cell_info",                       kind = "b", type = "proc($T: typeid)           -> ^runtime.Map_Cell_Info"},

	{name = "type_convert_variants_to_pointers",        kind = "b", type = "proc($T: typeid) -> typeid where type_is_union(T)"},
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

	{name = "simd_extract",            kind = "b", type = "proc(a: #simd[N]T, idx: uint) -> T"},
	{name = "simd_replace",            kind = "b", type = "proc(a: #simd[N]T, idx: uint, elem: T) -> #simd[N]T"},

	{name = "simd_reduce_add_ordered", kind = "b", type = "proc(a: #simd[N]T) -> T"},
	{name = "simd_reduce_mul_ordered", kind = "b", type = "proc(a: #simd[N]T) -> T"},
	{name = "simd_reduce_min",         kind = "b", type = "proc(a: #simd[N]T) -> T"},
	{name = "simd_reduce_max",         kind = "b", type = "proc(a: #simd[N]T) -> T"},
	{name = "simd_reduce_and",         kind = "b", type = "proc(a: #simd[N]T) -> T"},
	{name = "simd_reduce_or",          kind = "b", type = "proc(a: #simd[N]T) -> T"},
	{name = "simd_reduce_xor",         kind = "b", type = "proc(a: #simd[N]T) -> T"},

	{name = "simd_shuffle",            kind = "b", type = "proc(a, b: #simd[N]T, indices: ..int) -> #simd[len(indices)]T"},
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
	{name = "x86_cpuid",  kind = "b", type = "proc(ax, cx: u32) -> (eax, ebx, ecx, edx: u32)", comment = X86_COMMENT},
	{name = "x86_xgetbv", kind = "b", type = "proc(cx: u32) -> (eax, edx: u32)", comment = X86_COMMENT},


	// Darwin targets only
	{name = "objc_object",            kind = "t", type="struct{}",                              comment = DARWIN_COMMENT},
	{name = "objc_selector",          kind = "t", type="struct{}",                              comment = DARWIN_COMMENT},
	{name = "objc_class",             kind = "t", type="struct{}",                              comment = DARWIN_COMMENT},
	{name = "objc_id",                kind = "t", type="^objc_object",                          comment = DARWIN_COMMENT},
	{name = "objc_SEL",               kind = "t", type="^objc_selector",                        comment = DARWIN_COMMENT},
	{name = "objc_Class",             kind = "t", type="^objc_class",                           comment = DARWIN_COMMENT},

	{name = "objc_find_selector",     kind = "b", type="proc($name: string) -> objc_SEL   ---", comment = DARWIN_COMMENT},
	{name = "objc_register_selector", kind = "b", type="proc($name: string) -> objc_SEL   ---", comment = DARWIN_COMMENT},
	{name = "objc_find_class",        kind = "b", type="proc($name: string) -> objc_Class ---", comment = DARWIN_COMMENT},
	{name = "objc_register_class",    kind = "b", type="proc($name: string) -> objc_Class ---", comment = DARWIN_COMMENT},
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