package odin_html_docs

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:strconv"
import "core:strings"

import "core:odin/ast"
import doc "core:odin/doc-format"
import "core:odin/parser"
import "core:odin/tokenizer"

Int_Value :: struct {
	value:  i128,
	bits:   int, // 0 when untyped
	signed: bool,
}

Enum_Member :: struct {
	name:  string,
	value: i128,
	known: bool,
}

// the elements of a bit_set: bit `i` is element `lower + i`
Set_Type :: struct {
	lower:   i128,
	all:     u128, // every element
	members: []Enum_Member,
	runes:   bool,
}

constant_values:   map[^doc.Entity]Maybe(Int_Value)
constant_sets:     map[^doc.Entity]Maybe(u128)
constants_by_name: map[^doc.Pkg]map[string]^doc.Entity
enum_members_of:   map[^doc.Entity][]Enum_Member // by the first member

constant_value :: proc(e: ^doc.Entity, depth := 0) -> (v: Int_Value, ok: bool) {
	if e.kind != .Constant {
		return
	}
	if cached, found := constant_values[e]; found {
		return cached.?
	}
	if depth > 32 {
		return
	}
	constant_values[e] = nil // a constant defined in terms of itself has no value

	pkg := &cfg.pkgs[cfg.files[e.pos.file].pkg]
	value := eval_integer(str(e.init_string), pkg, nil, depth+1) or_return

	v = int_value_of_type(value, cfg.types[e.type]) or_return
	constant_values[e] = v
	return v, true
}

constant_hover :: proc(e: ^doc.Entity) -> (res: string) {
	if set, is_set := set_type_of(cfg.types[e.type]); is_set {
		return constant_set_hover(e, &set)
	}
	v, ok := constant_value(e)
	if !ok || adds_nothing(str(e.init_string), v) {
		return
	}
	return format_int_value(v, str(e.init_string))
}

adds_nothing :: proc(literal: string, v: Int_Value) -> bool {
	s := strings.trim_prefix(strings.trim_space(literal), "-")
	if s == "" {
		return false
	}
	for c in transmute([]byte)s {
		if !('0' <= c && c <= '9' || c == '_') {
			return false
		}
	}
	// a decimal literal, which only needs its hexadecimal form shown
	return 0 <= v.value && v.value < 10 || v.value < 0 && v.bits == 0
}

int_value_of_type :: proc(value: i128, t: doc.Type) -> (v: Int_Value, ok: bool) {
	bt := base_type(t)
	if bt.kind != .Basic {
		return
	}
	v = Int_Value{value = value, signed = true}
	name := str(bt.name)
	if is_type_untyped(bt) {
		return v, strings.contains(name, "integer") || strings.contains(name, "rune")
	}

	name = strings.trim_suffix(strings.trim_suffix(name, "le"), "be")
	switch name {
	case "int":     v.bits = 64
	case "uint":    v.bits, v.signed = 64, false
	case "uintptr": v.bits, v.signed = 64, false
	case "byte":    v.bits, v.signed = 8, false
	case "rune":    v.bits = 32
	case:
		if len(name) < 2 || (name[0] != 'i' && name[0] != 'u') {
			return
		}
		for c in transmute([]byte)name[1:] {
			if !('0' <= c && c <= '9') {
				return
			}
			v.bits = v.bits*10 + int(c - '0')
		}
		v.signed = name[0] == 'i'
	}

	if 0 < v.bits && v.bits < 128 {
		size := i128(1) << uint(v.bits)
		v.value &= size - 1
		if v.signed && v.value >= size/2 {
			v.value -= size
		}
	}
	return v, true
}

format_int_value :: proc(v: Int_Value, source := "") -> string {
	// `_` every `size` digits from the right, once there are more than four
	grouped :: proc(digits: string, size: int) -> string {
		if len(digits) <= 4 {
			return digits
		}
		b := strings.builder_make(context.temp_allocator)
		for c, i in transmute([]byte)digits {
			if i > 0 && (len(digits)-i) % size == 0 {
				strings.write_byte(&b, '_')
			}
			strings.write_byte(&b, c)
		}
		return strings.to_string(b)
	}

	negative := v.value < 0
	magnitude := u128(-v.value) if negative else u128(v.value)
	decimal := grouped(fmt.tprintf("%d", magnitude), 3)
	if negative {
		decimal = fmt.tprintf("-%s", decimal)
	}
	if !negative && v.value < 10 {
		return fmt.tprintf("= %s", decimal)
	}

	// the bits as stored, which an untyped negative value has none of
	stored, has_stored := magnitude, !negative
	if negative && v.bits > 0 {
		stored, has_stored = u128(v.value), true
		if v.bits < 128 {
			stored &= (u128(1) << uint(v.bits)) - 1
		}
	}

	// a single bit is clearer as `1 << n` than as its hexadecimal
	second := ""
	if has_stored && stored & (stored - 1) == 0 {
		if !is_shift_literal(source) {
			second = fmt.tprintf("1 << %d", intrinsics.count_trailing_zeros(stored))
		}
	} else if !is_hex_literal(source) {
		hex := grouped(fmt.tprintf("%X", stored if has_stored else magnitude), 4)
		second = fmt.tprintf("0x%s", hex) if has_stored else fmt.tprintf("-0x%s", hex)
	}

	if second == "" {
		return fmt.tprintf("= %s", decimal)
	}
	return fmt.tprintf("= %s (%s)", decimal, second)
}

@(private="file")
is_hex_literal :: proc(source: string) -> bool {
	s := strings.trim_prefix(strings.trim_space(source), "-")
	if !strings.has_prefix(s, "0x") && !strings.has_prefix(s, "0X") || len(s) == 2 {
		return false
	}
	for c in transmute([]byte)s[2:] {
		if !('0' <= c && c <= '9' || 'a' <= c && c <= 'f' || 'A' <= c && c <= 'F' || c == '_') {
			return false
		}
	}
	return true
}

@(private="file")
is_shift_literal :: proc(source: string) -> bool {
	s, _ := strings.remove_all(source, " ", context.temp_allocator)
	s = strings.trim_space(s)
	if !strings.has_prefix(s, "1<<") || len(s) == 3 {
		return false
	}
	for c in transmute([]byte)s[3:] {
		if !('0' <= c && c <= '9') {
			return false
		}
	}
	return true
}


// `locals` are, e.g., the members of an enum before the one being worked out
eval_integer :: proc(src: string, pkg: ^doc.Pkg, locals: ^map[string]i128, depth := 0) -> (value: i128, ok: bool) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	return eval_expr(parse_value(src), pkg, locals, depth)
}

@(private="file")
parse_value :: proc(src: string) -> ^ast.Expr {
	context.allocator = context.temp_allocator

	p := parser.default_parser()
	p.err  = proc(pos: tokenizer.Pos, msg: string, args: ..any) {}
	p.warn = p.err
	file := ast.File{src = src, fullpath = "constant value"}
	p.file = &file
	tokenizer.init(&p.tok, src, file.fullpath, p.err)
	parser.advance_token(&p)
	expr := parser.parse_expr(&p, false)
	if p.error_count > 0 || p.curr_tok.kind != .EOF {
		return nil
	}
	return expr
}

enum_members :: proc(t: doc.Type) -> []Enum_Member {
	entities := array(t.entities)
	if len(entities) == 0 {
		return nil
	}
	key := &cfg.entities[entities[0]]
	if members, ok := enum_members_of[key]; ok {
		return members
	}

	members := make([]Enum_Member, len(entities))
	locals: map[string]i128
	defer delete(locals)
	value, known := i128(-1), true
	for entity_index, i in entities {
		e := &cfg.entities[entity_index]
		name, init := str(e.name), str(e.init_string)
		if init == "" {
			value += 1
		} else {
			value, known = eval_integer(init, &cfg.pkgs[cfg.files[e.pos.file].pkg], &locals)
		}
		members[i] = {name, value, known}
		if known {
			locals[name] = value
		}
	}
	enum_members_of[key] = members
	return members
}

set_type_of :: proc(t: doc.Type) -> (set: Set_Type, ok: bool) {
	bt := base_type(t)
	if bt.kind != .Bit_Set {
		return
	}
	types := array(bt.types)
	lower, upper := i128(bt.elem_counts[0]), i128(bt.elem_counts[1])
	// as the compiler does, a backing type starts the bits at zero
	set.lower = min(0, lower) if .Underlying_Type in transmute(doc.Type_Flags_Bit_Set)bt.flags else lower
	if upper - set.lower >= 128 {
		return
	}

	if len(types) > 0 {
		elem := base_type(cfg.types[types[0]])
		if elem.kind == .Enum {
			set.members = enum_members(elem)
		}
		set.runes = elem.kind == .Basic && str(elem.name) == "rune"
	}
	if set.members != nil {
		for m in set.members {
			if !m.known {
				return
			}
			set.all |= u128(1) << uint(m.value - set.lower)
		}
	} else {
		for v in lower..=upper {
			set.all |= u128(1) << uint(v - set.lower)
		}
	}
	return set, true
}

constant_set_value :: proc(e: ^doc.Entity, set: ^Set_Type, depth := 0) -> (bits: u128, ok: bool) {
	if e.kind != .Constant {
		return
	}
	if cached, found := constant_sets[e]; found {
		return cached.?
	}
	if depth > 32 {
		return
	}
	constant_sets[e] = nil

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	pkg := &cfg.pkgs[cfg.files[e.pos.file].pkg]
	bits = eval_set(parse_value(str(e.init_string)), set, pkg, depth+1) or_return
	constant_sets[e] = bits
	return bits, true
}

constant_set_hover :: proc(e: ^doc.Entity, set: ^Set_Type) -> string {
	{
		runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
		// one that lists its elements already says it
		if expr := parse_value(str(e.init_string)); expr != nil {
			if _, is_literal := expr.derived_expr.(^ast.Comp_Lit); is_literal {
				return ""
			}
		}
	}
	bits, ok := constant_set_value(e, set)
	if !ok {
		return ""
	}

	elems := make([dynamic]string, context.temp_allocator)
	for i in 0..<128 {
		if bits & (u128(1) << uint(i)) == 0 {
			continue
		}
		v := set.lower + i128(i)
		name := ""
		for m in set.members {
			if m.value == v {
				name = fmt.tprintf(".%s", m.name)
				break
			}
		}
		switch {
		case name != "":
		case set.runes:
			name = fmt.tprintf("%q", rune(v))
		case:
			name = fmt.tprintf("%d", v)
		}
		append(&elems, name)
	}
	return fmt.tprintf("= {{%s}}", strings.join(elems[:], ", ", context.temp_allocator))
}

@(private="file")
eval_set :: proc(expr: ^ast.Expr, set: ^Set_Type, pkg: ^doc.Pkg, depth: int) -> (bits: u128, ok: bool) {
	if expr == nil {
		return
	}
	#partial switch e in expr.derived_expr {
	case ^ast.Comp_Lit:
		for elem in e.elems {
			v := set_element(elem, set, pkg, depth) or_return
			bit := v - set.lower
			if bit < 0 || bit >= 128 {
				return
			}
			bits |= u128(1) << uint(bit)
		}
		return bits, true

	case ^ast.Ident:
		constant := constants_of(pkg)[e.name] or_return
		return constant_set_value(constant, set, depth+1)

	case ^ast.Paren_Expr:
		return eval_set(e.expr, set, pkg, depth)

	case ^ast.Unary_Expr:
		x := eval_set(e.expr, set, pkg, depth) or_return
		#partial switch e.op.kind {
		case .Add: return x, true
		case .Xor: return ~x & set.all, true // as the compiler does, the complement is of the elements
		}

	case ^ast.Binary_Expr:
		x := eval_set(e.left,  set, pkg, depth) or_return
		y := eval_set(e.right, set, pkg, depth) or_return
		#partial switch e.op.kind {
		case .Add, .Or: return x | y, true
		case .Sub:      return x &~ y, true
		case .And:      return x & y, true
		case .Xor:      return x ~ y, true
		}

	case ^ast.Type_Cast:
		// `transmute(Flags)u32(0xc0000000)` takes the bits as they are
		if e.tok.kind == .Transmute {
			v := eval_expr(e.expr, pkg, nil, depth) or_return
			return u128(v), true
		}
	}
	return
}

@(private="file")
set_element :: proc(elem: ^ast.Expr, set: ^Set_Type, pkg: ^doc.Pkg, depth: int) -> (value: i128, ok: bool) {
	field := ""
	#partial switch e in elem.derived_expr {
	case ^ast.Implicit_Selector_Expr:
		field = e.field.name
	case ^ast.Selector_Expr:
		field = e.field.name
	}
	if field != "" {
		for m in set.members {
			if m.name == field && m.known {
				return m.value, true
			}
		}
		return
	}
	return eval_expr(elem, pkg, nil, depth)
}

@(private="file")
eval_expr :: proc(expr: ^ast.Expr, pkg: ^doc.Pkg, locals: ^map[string]i128, depth: int) -> (value: i128, ok: bool) {
	if expr == nil {
		return
	}
	#partial switch e in expr.derived_expr {
	case ^ast.Basic_Lit:
		#partial switch e.tok.kind {
		case .Integer:
			return parse_integer_literal(e.tok.text)
		case .Rune:
			text := e.tok.text
			if len(text) < 3 {
				return
			}
			r, _, rest, unquoted := strconv.unquote_char(text[1:len(text)-1], '\'')
			if !unquoted || rest != "" {
				return
			}
			return i128(r), true
		}

	case ^ast.Ident:
		if locals != nil {
			if local, found := locals[e.name]; found {
				return local, true
			}
		}
		if pkg == nil {
			return
		}
		constant := constants_of(pkg)[e.name] or_return

		v := constant_value(constant, depth+1) or_return
		return v.value, true

	case ^ast.Paren_Expr:
		return eval_expr(e.expr, pkg, locals, depth)

	case ^ast.Unary_Expr:
		x := eval_expr(e.expr, pkg, locals, depth) or_return
		#partial switch e.op.kind {
		case .Add: return  x, true
		case .Sub: return -x, true
		case .Xor: return ~x, true
		}

	case ^ast.Binary_Expr:
		x := eval_expr(e.left,  pkg, locals, depth) or_return
		y := eval_expr(e.right, pkg, locals, depth) or_return
		#partial switch e.op.kind {
		case .Add:     return x + y, true
		case .Sub:     return x - y, true
		case .Mul:     return x * y, true
		case .Or:      return x | y, true
		case .Xor:     return x ~ y, true
		case .And:     return x & y, true
		case .And_Not: return x &~ y, true
		case .Quo, .Mod, .Mod_Mod:
			if y == 0 {
				return
			}
			#partial switch e.op.kind {
			case .Quo: return x / y, true
			case .Mod: return x % y, true
			case:      return x %% y, true
			}
		case .Shl, .Shr:
			if y < 0 || y > 127 {
				return
			}
			return (x << uint(y)) if e.op.kind == .Shl else (x >> uint(y)), true
		}

	case ^ast.Call_Expr:
		// a conversion such as `u32(x)` or `DWORD(x)` keeps the value, but a call such as `size_of(T)` has none here
		ident := e.expr.derived_expr.(^ast.Ident) or_return
		if len(e.args) != 1 || !is_integer_type_name(pkg, ident.name) {
			return
		}
		return eval_expr(e.args[0], pkg, locals, depth)

	case ^ast.Type_Cast:
		if e.tok.kind == .Cast {
			return eval_expr(e.expr, pkg, locals, depth)
		}

	case ^ast.Auto_Cast:
		return eval_expr(e.expr, pkg, locals, depth)
	}
	return
}

@(private="file")
is_integer_type_name :: proc(pkg: ^doc.Pkg, name: string) -> bool {
	switch strings.trim_suffix(strings.trim_suffix(name, "le"), "be") {
	case "int", "uint", "uintptr", "byte", "rune",
	     "i8", "i16", "i32", "i64", "i128",
	     "u8", "u16", "u32", "u64", "u128":
		return true
	}
	if pkg == nil {
		return false
	}
	for entry in array(pkg.entries) {
		e := &cfg.entities[entry.entity]
		if e.kind == .Type_Name && str(entry.name) == name {
			_, ok := int_value_of_type(0, cfg.types[e.type])
			return ok
		}
	}
	return false
}

@(private="file")
constants_of :: proc(pkg: ^doc.Pkg) -> map[string]^doc.Entity {
	if names, ok := constants_by_name[pkg]; ok {
		return names
	}
	names: map[string]^doc.Entity
	for entry in array(pkg.entries) {
		e := &cfg.entities[entry.entity]
		if e.kind == .Constant {
			names[str(entry.name)] = e
		}
	}
	constants_by_name[pkg] = names
	return names
}
