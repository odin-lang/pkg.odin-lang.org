package bundle_examples

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/slashpath"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"

FORMAT_VERSION :: 2

Examples_Bundle :: struct {
	format:   int,
	repo:     string, // "https://github.com/odin-lang/examples"
	commit:   string, // the commit the sources are from, which links to them point at
	programs: []Example_Program,
}

Example_Program :: struct {
	path:      string,
	readme:    string,
	license:   Example_License,
	link_only: bool,   // its code is only linked to, not shown, as its licence may ask
	files:     []Example_File,
	other:     []Example_File,  // its other text, like shaders, scripts and data, by their paths in its folder
	assets:    []Example_Asset, // and the rest, like images and fonts, only by name
}

Example_License :: struct {
	path: string, // "opengl/learn_opengl/LICENSE"
	text: string,
}

Example_File :: struct {
	name:      string, // "main.odin"
	source:    string,
	truncated: bool,   // only the start of it, as it's long
}

Example_Asset :: struct {
	name: string, // "res/font.png"
	size: i64,
}

// Text longer than this is only its start
MAX_TEXT :: 32 * 1024


USAGE :: ```
usage: bundle_examples <examples checkout> <bundle.json> [-link-only:<program>]...

Bundles the sources of a checkout of https://github.com/odin-lang/examples for the docs generator,
which takes it with -examples:<bundle.json>.

	-link-only:<program>   only link to the program, or the programs under it, rather than show their code,
	                       e.g. -link-only:opengl/learn_opengl for a licence that asks for that
```

main :: proc() {
	repo_url :: proc(checkout: string) -> string {
		DEFAULT :: "https://github.com/odin-lang/examples"
		config, ok := read_text(slashpath.join({git_dir(checkout), "config"}))
		if !ok {
			return DEFAULT
		}
		in_origin := false
		for raw in strings.split_lines_iterator(&config) {
			line := strings.trim_space(raw)
			if strings.has_prefix(line, "[") {
				in_origin = line == `[remote "origin"]`
				continue
			}
			key, _, value := strings.partition(line, "=")
			if !in_origin || strings.trim_space(key) != "url" {
				continue
			}
			url := strings.trim_suffix(strings.trim_space(value), ".git")
			if strings.has_prefix(url, "git@") {
				host, _, path := strings.partition(url[len("git@"):], ":")
				url = fmt.aprintf("https://%s/%s", host, path)
			}
			return url
		}
		return DEFAULT
	}


	head_commit :: proc(checkout: string) -> string {
		git := git_dir(checkout)
		head, ok := read_text(slashpath.join({git, "HEAD"}))
		if !ok {
			return ""
		}
		head = strings.trim_space(head)
		if !strings.has_prefix(head, "ref:") {
			return head
		}
		ref := strings.trim_space(head[len("ref:"):])
		if hash, found := read_text(slashpath.join({git, ref})); found {
			return strings.trim_space(hash)
		}
		// or among the packed ones, as "<hash> <ref>"
		packed, _ := read_text(slashpath.join({git, "packed-refs"}))
		for line in strings.split_lines_iterator(&packed) {
			if hash, _, name := strings.partition(line, " "); name == ref {
				return hash
			}
		}
		return ""
	}

	checkout, out: string
	link_only: [dynamic]string
	for arg in os.args[1:] {
		switch {
		case strings.has_prefix(arg, "-link-only:"):
			append(&link_only, strings.trim_right(arg[len("-link-only:"):], "/"))
		case checkout == "":
			checkout = arg
		case out == "":
			out = arg
		case:
			fmt.eprint(USAGE)
			os.exit(1)
		}
	}
	if checkout == "" || out == "" {
		fmt.eprint(USAGE)
		os.exit(1)
	}
	checkout = strings.trim_right(checkout, "/\\")

	programs: [dynamic]Example_Program
	collect(checkout, "", &programs, link_only[:])
	slice.sort_by(programs[:], proc(a, b: Example_Program) -> bool {
		return a.path < b.path
	})

	bundle := Examples_Bundle{
		format   = FORMAT_VERSION,
		repo     = repo_url(checkout),
		commit   = head_commit(checkout),
		programs = programs[:],
	}
	data, err := json.marshal(bundle, opt={pretty=true})
	if err != nil {
		fmt.eprintfln("unable to write the bundle: %v", err)
		os.exit(1)
	}
	if write_err := os.write_entire_file(out, data); write_err != nil {
		fmt.eprintfln("unable to write %s: %v", out, write_err)
		os.exit(1)
	}

	files, other, assets := 0, 0, 0
	for p in programs {
		files  += len(p.files)
		other  += len(p.other)
		assets += len(p.assets)
	}
	fmt.printfln("%d programs, %d .odin files, %d other files, %d assets, from %s at %s", len(programs), files, other, assets, bundle.repo, bundle.commit)
}

collect :: proc(checkout, rel: string, programs: ^[dynamic]Example_Program, link_only: []string) {
	own_license :: proc(checkout, rel: string) -> (license: Example_License) {
		// the nearest in the program's folder or one above it, but not one for some of its assets,
		// like `LICENSE.SDL2.txt`, nor the repo's own
		NAMES :: []string{"LICENSE", "LICENSE.md", "LICENSE.txt", "COPYING", "COPYING.md", "COPYING.txt"}
		for dir := rel; dir != "" && dir != "."; dir = slashpath.dir(dir) {
			for name in NAMES {
				path := slashpath.join({dir, name})
				if text, ok := read_text(slashpath.join({checkout, path})); ok {
					return {path = path, text = text}
				}
			}
			strings.contains_rune(dir, '/') or_break
		}
		return
	}

	// every folder with .odin files is a program
	dir := slashpath.join({checkout, rel}) if rel != "" else checkout
	entries, err := os.read_all_directory_by_path(dir, context.allocator)
	if err != nil {
		fmt.eprintfln("unable to read %s: %v", dir, err)
		return
	}
	slice.sort_by(entries, proc(a, b: os.File_Info) -> bool {
		return a.name < b.name
	})

	gather :: proc(checkout, program, sub, skip: string, other: ^[dynamic]Example_File, assets: ^[dynamic]Example_Asset) {
		entries, err := os.read_all_directory_by_path(slashpath.join({checkout, program, sub}), context.allocator)
		if err != nil {
			return
		}
		slice.sort_by(entries, proc(a, b: os.File_Info) -> bool {
			return a.name < b.name
		})
		for entry in entries {
			// a folder with .odin files is a program of its own
			if sub != "" && strings.has_suffix(entry.name, ".odin") {
				return
			}
		}
		for entry in entries {
			name := slashpath.join({sub, entry.name}) if sub != "" else entry.name
			switch {
			case strings.has_prefix(entry.name, "."):
			case entry.type == .Directory:
				gather(checkout, program, name, skip, other, assets)
			case sub == "" && (strings.has_suffix(entry.name, ".odin") || strings.to_lower(entry.name) == "readme.md"):
			case slashpath.join({program, name}) == skip:
			case:
				data, read_err := os.read_entire_file_from_path(entry.fullpath, context.allocator)
				if read_err != nil {
					continue
				}
				if slice.contains(data, 0) || !utf8.valid_string(string(data)) {
					append(assets, Example_Asset{name = name, size = i64(len(data))})
					continue
				}
				text, _ := strings.replace_all(string(data), "\r\n", "\n")
				truncated := len(text) > MAX_TEXT
				if truncated {
					cut := strings.last_index_byte(text[:MAX_TEXT], '\n')
					text = text[:cut + 1 if cut > 0 else MAX_TEXT]
				}
				append(other, Example_File{name = name, source = text, truncated = truncated})
			}
		}
	}

	program := Example_Program{path = rel}
	files: [dynamic]Example_File
	for entry in entries {
		switch {
		case entry.type == .Directory:
			if !strings.has_prefix(entry.name, ".") {
				collect(checkout, slashpath.join({rel, entry.name}) if rel != "" else entry.name, programs, link_only)
			}
		case strings.has_suffix(entry.name, ".odin"):
			if source, ok := read_text(entry.fullpath); ok {
				append(&files, Example_File{name = entry.name, source = source})
			}
		case strings.to_lower(entry.name) == "readme.md":
			program.readme, _ = read_text(entry.fullpath)
		}
	}
	if len(files) == 0 || rel == "" {
		return
	}
	program.files = files[:]
	program.license = own_license(checkout, rel)

	other: [dynamic]Example_File
	assets: [dynamic]Example_Asset
	gather(checkout, rel, "", program.license.path, &other, &assets)
	program.other = other[:]
	program.assets = assets[:]
	for path in link_only {
		if rel == path || strings.has_prefix(rel, path) && strings.has_prefix(rel[len(path):], "/") {
			program.link_only = true
		}
	}
	append(programs, program)
}


read_text :: proc(path: string) -> (text: string, ok: bool) {
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {
		return
	}
	text = string(data)
	text, _ = strings.replace_all(text, "\r\n", "\n")
	return text, true
}

git_dir :: proc(checkout: string) -> string {
	dot_git := slashpath.join({checkout, ".git"})
	if text, ok := read_text(dot_git); ok && strings.has_prefix(text, "gitdir:") {
		dir := strings.trim_space(text[len("gitdir:"):])
		return dir if slashpath.is_abs(dir) || strings.contains_rune(dir, ':') else slashpath.join({checkout, dir})
	}
	return dot_git
}