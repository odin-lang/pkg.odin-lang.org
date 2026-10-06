package odin_html_docs

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:path/slashpath"
import "core:slice"
import "core:strings"

import doc "core:odin/doc-format"

// Each doc file is one target's build, so a package in several of them has a copy in each, and a copy may
// declare what the others don't, like `core:fmt`'s `stdout` in a JS build. A package's page is one copy's,
// with what only the others declare after it.

pkg_copies: map[string][dynamic]^doc.Pkg // by full path

Pkg_Extra :: struct {
	copy:    ^doc.Pkg, // one that declares it
	entry:   doc.Scope_Entry,
	name:    string,
	targets: [dynamic]string, // the builds that declare it, like "Windows"
}

pkg_extras: map[^doc.Pkg][dynamic]Pkg_Extra // by copy: what only other copies declare

Pkg_Extra_Group :: struct {
	label:  string, // "Windows", or "Linux, macOS"
	slug:   string,
	extras: [dynamic]Pkg_Extra,
}

merge_pkg_copies :: proc() {
	context.allocator = runtime.default_allocator()
	for _, copies in pkg_copies {
		if len(copies) < 2 {
			continue
		}
		// every copy is the one page's, so its declarations can be shown there and links into it go there
		collection: ^Collection
		path: string
		for c in copies {
			if col := cfg.pkg_to_collection[c]; col != nil {
				collection, path = col, col.pkg_to_path[c]
				break
			}
		}
		if collection == nil {
			continue
		}
		for c in copies {
			if c not_in cfg.pkg_to_collection {
				cfg.pkg_to_collection[c] = collection
				collection.pkg_to_path[c] = path
			}
		}

		names := make([]map[string]doc.Scope_Entry, len(copies), context.temp_allocator)
		for c, i in copies {
			names[i] = pkg_public_entries(c)
		}
		for c, i in copies {
			extras: [dynamic]Pkg_Extra
			for other, j in copies {
				if j == i {
					continue
				}
				target := header_target(cfg.pkg_to_header[other])
				other_names: for name, entry in names[j] {
					if name in names[i] {
						continue
					}
					for &x in extras {
						if x.name == name {
							if target != "" && !slice.contains(x.targets[:], target) {
								append(&x.targets, target)
							}
							continue other_names
						}
					}
					x := Pkg_Extra{copy = other, entry = entry, name = name}
					if target != "" {
						append(&x.targets, target)
					}
					append(&extras, x)
				}
			}
			if len(extras) > 0 {
				slice.sort_by(extras[:], proc(a, b: Pkg_Extra) -> bool {
					return a.name < b.name
				})
				pkg_extras[c] = extras
			}
		}
	}
}

is_first_build_pkg :: proc(fullpath: string) -> bool {
	// by its import path, found as `generate_from_path` finds it
	for c in cfg.collections {
		if !strings.has_prefix(fullpath, c.root_path) {
			continue
		}
		path := strings.trim_prefix(fullpath, c.root_path)
		path = strings.trim_prefix(path, c.base_url[1:])
		path = strings.trim_prefix(path, "/")
		import_path := fmt.tprintf("%s:%s", c.name, path)
		for pattern in cfg.first_build_packages {
			if import_path_matches(pattern, import_path) {
				return true
			}
		}
		return false
	}
	return false
}

@(private="file")
pkg_public_entries :: proc(pkg: ^doc.Pkg) -> map[string]doc.Scope_Entry {
	// as `pkg_entries_gather` takes them
	header := cfg.pkg_to_header[pkg]
	entities := doc.from_array(header, header.entities)
	pkg_name := doc.from_string(header, pkg.name)
	names := make(map[string]doc.Scope_Entry, context.temp_allocator)
	for entry in doc.from_array(header, pkg.entries) {
		e := entities[entry.entity]
		#partial switch e.kind {
		case .Invalid, .Import_Name, .Library_Name:
			continue
		}
		entity_name, name := doc.from_string(header, e.name), doc.from_string(header, entry.name)
		hidden :: proc(name, pkg_name: string) -> bool {
			return name == "" || name[0] == '_' && !strings.has_prefix(pkg_name, "simd")
		}
		if hidden(entity_name, pkg_name) || hidden(name, pkg_name) {
			continue
		}
		names[name] = entry
	}
	return names
}

header_target :: proc(header: ^doc.Header) -> string {
	// the operating system whose files, like `os_windows.odin`, the build has
	oses := [?][2]string{
		{"windows", "Windows"}, {"darwin", "macOS"}, {"linux", "Linux"}, {"freebsd", "FreeBSD"}, {"openbsd", "OpenBSD"},
		{"netbsd", "NetBSD"}, {"haiku", "Haiku"}, {"js", "JS"}, {"wasi", "WASI"}, {"orca", "Orca"},
	}
	ARCHES :: []string{"amd64", "arm64", "i386", "arm32", "wasm32", "wasm64p32", "riscv64"}
	@(static) targets: map[^doc.Header]string
	if target, ok := targets[header]; ok {
		return target
	}
	counts: [len(oses)]int
	for file in doc.from_array(header, header.files)[1:] {
		name, _ := strings.replace_all(doc.from_string(header, file.name), "\\", "/", context.temp_allocator)
		parts := strings.split(strings.trim_suffix(slashpath.base(name), ".odin"), "_", context.temp_allocator)
		if len(parts) > 2 && slice.contains(ARCHES, parts[len(parts)-1]) {
			parts = parts[:len(parts)-1]
		}
		for os, i in oses {
			if len(parts) > 1 && parts[len(parts)-1] == os[0] {
				counts[i] += 1
			}
		}
	}
	best := -1
	for count, i in counts {
		if count > 0 && (best < 0 || count > counts[best]) {
			best = i
		}
	}
	target := oses[best][1] if best >= 0 else ""
	targets[header] = target
	return target
}

pkg_extra_groups :: proc(pkg: ^doc.Pkg) -> []Pkg_Extra_Group {
	// by the builds that declare them
	groups := make([dynamic]Pkg_Extra_Group, context.temp_allocator)
	extras_loop: for x in pkg_extras[pkg] or_else nil {
		targets := slice.clone(x.targets[:], context.temp_allocator)
		slice.sort(targets)
		label := strings.join(targets, ", ", context.temp_allocator) if len(targets) > 0 else "other targets"
		for &g in groups {
			if g.label == label {
				append(&g.extras, x)
				continue extras_loop
			}
		}
		g := Pkg_Extra_Group{label = label, slug = slugify(fmt.tprintf("only on %s", label), context.temp_allocator)}
		g.extras = make([dynamic]Pkg_Extra, context.temp_allocator)
		append(&g.extras, x)
		append(&groups, g)
	}
	return groups[:]
}

write_pkg_extras :: proc(w: io.Writer, pkg: ^doc.Pkg) {
	groups := pkg_extra_groups(pkg)
	if len(groups) == 0 {
		return
	}
	page_target := header_target(cfg.pkg_to_header[pkg])
	fmt.wprintln(w, `<section class="documentation">`)
	for g in groups {
		fmt.wprintf(w, `<h2 id="pkg-%s" class="pkg-header">Only on %s <span class="pkg-count">%d</span></h2>`+"\n", g.slug, g.label, len(g.extras))
		if page_target != "" {
			fmt.wprintf(w, `<p class="pkg-examples-note">Declared only when building for %s; the rest of this page is from a %s build.</p>`+"\n", g.label, page_target)
		}
		for x in g.extras {
			// in the copy that declares it, under the page's report
			init_cfg_from_pkg(x.copy)
			if x.copy not_in report_pkgs {
				report_pkgs[x.copy] = report_of(pkg)
			}
			fmt.wprintln(w, `<div class="pkg-entity">`)
			write_entry(w, x.copy, x.entry)
			fmt.wprintln(w, `</div>`)
		}
	}
	init_cfg_from_pkg(pkg)
	fmt.wprintln(w, "</section>")
}

write_pkg_extras_toc :: proc(w: io.Writer, pkg: ^doc.Pkg) {
	for g in pkg_extra_groups(pkg) {
		fmt.wprintf(w, `<li><a href="#pkg-%s">Only on %s<span class="toc-count">%d</span></a><ul>`+"\n", g.slug, g.label, len(g.extras))
		for x in g.extras {
			fmt.wprintf(w, `<li><a href="#%s">`, x.name)
			write_breakable_name(w, x.name)
			io.write_string(w, "</a></li>\n")
		}
		io.write_string(w, "</ul></li>\n")
	}
}
