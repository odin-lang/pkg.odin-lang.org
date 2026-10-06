package odin_html_docs

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:os"
import "core:path/slashpath"
import "core:slice"
import "core:strings"

import doc "core:odin/doc-format"

import be "bundle_examples"

// A page for each example at EXAMPLES_URL/<path>/, with its code in full and the names in it linked to their docs,
// and EXAMPLES_URL/ listing them all

// Other text longer than this is only linked to
EXAMPLE_SHOWN_MAX_LINES :: 100

// Unless the reader has chosen another, which is kept for every example; style.css has it too
EXAMPLE_TAB_WIDTH :: 4

// In the head, so the code is never drawn first with the wrong width or wrapping: the reader's choices, kept for every example
EXAMPLE_CODE_VIEW_SCRIPT :: `<script>
	(() => {
		const read = key => { try { return localStorage.getItem(key); } catch (e) { return null; } };
		const save = (key, value) => { try { localStorage.setItem(key, value); } catch (e) {} };
		const root = document.documentElement;
		let width = read("example-tab-width");
		if (!/^[1-8]$/.test(width || "")) width = null;
		const apply_width = w => root.style.setProperty("--example-tab-width", w);
		if (width) apply_width(width);
		const wrap = read("example-wrap-lines") === "1";
		root.classList.toggle("example-wrap-lines", wrap);
		document.addEventListener("DOMContentLoaded", () => {
			const selects = document.querySelectorAll(".example-tab-width select");
			for (const select of selects) {
				if (width) select.value = width;
				select.addEventListener("change", () => {
					apply_width(select.value);
					for (const other of selects) other.value = select.value;
					save("example-tab-width", select.value);
				});
			}
			const boxes = document.querySelectorAll(".example-wrap input");
			for (const box of boxes) {
				box.checked = wrap;
				box.addEventListener("change", () => {
					root.classList.toggle("example-wrap-lines", box.checked);
					for (const other of boxes) other.checked = box.checked;
					save("example-wrap-lines", box.checked ? "1" : "0");
				});
			}
		});
	})();
</script>
`

generate_example_pages :: proc(b: ^strings.Builder) {
	if len(example_pages) == 0 {
		return
	}
	w := strings.to_writer(b)
	for page, index in example_pages {
		runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
		strings.builder_reset(b)
		write_html_header(w, fmt.tprintf("%s example - pkg.odin-lang.org", page.path), .Full_Width,
		                  description = example_description(index), extra_head = EXAMPLE_CODE_VIEW_SCRIPT)
		write_example_page(w, index)
		write_html_footer(w, "")
		dir := fmt.tprintf("%s/%s", EXAMPLES_URL[1:], page.path)
		recursive_make_directory(dir)
		_ = os.write_entire_file(fmt.tprintf("%s/index.html", dir), b.buf[:])
	}

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	strings.builder_reset(b)
	write_html_header(w, "Examples - pkg.odin-lang.org", .Full_Width,
	                  description = "Example Odin programs from odin-lang/examples, with the names in their code linked to their documentation.")
	write_examples_index(w)
	write_html_footer(w, "")
	_ = os.write_entire_file(fmt.tprintf("%s/index.html", EXAMPLES_URL[1:]), b.buf[:])
}

// From its README, or else the comment its code starts with
example_summary :: proc(index: int) -> string {
	page := example_pages[index]
	program := examples.programs[page.program]
	if page.file < 0 && program.readme != "" {
		if summary := doc_summary(program.readme); summary != "" {
			return summary
		}
	}
	file := page.file
	if file < 0 && len(page.members) == 0 {
		for info, fi in example_files[page.program] {
			if info.main {
				file = fi
				break
			}
		}
	}
	if file < 0 {
		return ""
	}
	return doc_summary(leading_comment(program.files[file].source))
}

// The screenshot a file of a folder of programs that are each a file has beside it, like raylib's ports have
example_screenshot :: proc(index: int) -> string {
	page := example_pages[index]
	if page.file < 0 {
		return ""
	}
	program := examples.programs[page.program]
	stem := strings.trim_suffix(program.files[page.file].name, ".odin")
	for asset in program.assets {
		if is_image(asset.name) && strings.trim_suffix(slashpath.base(asset.name), slashpath.ext(asset.name)) == stem {
			if src, shown := github_image_url(example_github_url(fmt.tprintf("%s/%s", program.path, asset.name))); shown {
				return src
			}
		}
	}
	return ""
}

Example_Platform :: struct {
	name, title: string,
}

example_platforms :: proc(index: int) -> []Example_Platform {
	// what the code says: a platform's packages imported by a file that's built for every target, like `core:sys/windows`,
	// and the web when a file is built for `js` or a script builds it with `-target:js_wasm32`
	PLATFORM_PACKAGES :: [][2]string{
		{"core:sys/windows", "Windows"}, {"vendor:directx", "Windows"}, {"vendor:windows", "Windows"},
		{"core:sys/darwin", "macOS"}, {"vendor:darwin", "macOS"},
		{"core:sys/linux", "Linux"},
		{"core:sys/orca", "Orca"},
		{"core:sys/wasm", "Web"},
	}
	page := example_pages[index]
	program := examples.programs[page.program]
	only := make([dynamic]string, context.temp_allocator)
	web := false
	for file, fi in program.files {
		if page.file >= 0 && fi != page.file {
			continue
		}
		info := example_files[page.program][fi]
		if conditional, for_js := file_target(file.name, info.build); conditional {
			web ||= for_js
			continue
		}
		for pkg in info.packages {
			path := pkg_import_path(pkg)
			for p in PLATFORM_PACKAGES {
				if (path == p[0] || strings.has_prefix(path, p[0]) && strings.has_prefix(path[len(p[0]):], "/")) && !slice.contains(only[:], p[1]) {
					append(&only, p[1])
				}
			}
		}
	}
	for other in program.other {
		if file_kind(other.name) == .Build && strings.contains(other.source, "-target:js_") {
			web = true
		}
	}

	platforms := make([dynamic]Example_Platform, context.temp_allocator)
	for name in only {
		if name != "Web" {
			append(&platforms, Example_Platform{name, fmt.tprintf("Only builds for %s", name)})
		}
	}
	if web || slice.contains(only[:], "Web") {
		append(&platforms, Example_Platform{"Web", "Builds for the web, with -target:js_wasm32"})
	}
	return platforms[:]
}

@(private="file")
file_target :: proc(name, build: string) -> (conditional, for_js: bool) {
	// by a `#+build` line, or by a name ending in a target, like `os_js.odin` or `raw_windows.odin`
	if build != "" {
		for alternative in strings.split(build, ",", context.temp_allocator) {
			for term in strings.fields(alternative, context.temp_allocator) {
				for_js ||= term == "js"
			}
		}
		return true, for_js
	}
	TARGETS :: []string{
		"windows", "linux", "darwin", "freebsd", "openbsd", "netbsd", "haiku", "essence", "freestanding", "wasi", "js", "orca",
		"amd64", "arm64", "i386", "arm32", "wasm32", "wasm64p32", "riscv64",
	}
	parts := strings.split(strings.trim_suffix(name, ".odin"), "_", context.temp_allocator)
	if len(parts) < 2 || !slice.contains(TARGETS, parts[len(parts)-1]) {
		return false, false
	}
	for_js = parts[len(parts)-1] == "js" || len(parts) > 2 && parts[len(parts)-2] == "js"
	return true, for_js
}

// With its screenshot, if it has one, to show when the link's hovered
write_example_link_open :: proc(w: io.Writer, index: int) {
	fmt.wprintf(w, `<a href="%s"`, example_url(index))
	if screenshot := example_screenshot(index); screenshot != "" {
		fmt.wprintf(w, ` data-screenshot="%s"`, escape_html_text(screenshot))
	}
	io.write_string(w, ">")
}

write_example_platforms :: proc(w: io.Writer, index: int) {
	for p in example_platforms(index) {
		fmt.wprintf(w, ` <span class="doc-badge" title="%s">%s</span>`, p.title, p.name)
	}
}

@(private="file")
leading_comment :: proc(src: string) -> string {
	// the text of `// …` lines or a `/* … */` block, without the rows of `*` around it
	rest := strings.trim_left_space(src)
	for strings.has_prefix(rest, "#+") {
		_, _, rest = strings.partition(rest, "\n")
		rest = strings.trim_left_space(rest)
	}
	text: string
	switch {
	case strings.has_prefix(rest, "/*"):
		end := strings.index(rest, "*/")
		text = rest[2:end if end >= 0 else len(rest)]
	case strings.has_prefix(rest, "//"):
		lines := strings.builder_make(context.temp_allocator)
		for line in strings.split_lines_iterator(&rest) {
			t := strings.trim_left_space(line)
			if !strings.has_prefix(t, "//") {
				break
			}
			strings.write_string(&lines, t[2:])
			strings.write_byte(&lines, '\n')
		}
		text = strings.to_string(lines)
	case:
		return ""
	}
	b := strings.builder_make(context.temp_allocator)
	for line in strings.split_lines_iterator(&text) {
		t := strings.trim_space(strings.trim_left(strings.trim_space(line), "*"))
		if strings.trim(t, "*=-/ \t") == "" && t != "" {
			continue
		}
		strings.write_string(&b, t)
		strings.write_byte(&b, '\n')
	}
	return strings.to_string(b)
}

@(private="file")
example_description :: proc(index: int) -> string {
	if summary := example_summary(index); summary != "" {
		return summary
	}
	page := example_pages[index]
	if len(page.members) > 0 {
		return fmt.tprintf("Odin example programs, one to a file, from odin-lang/examples: %s.", page.path)
	}
	packages := page_packages(index)
	if len(packages) == 0 {
		return fmt.tprintf("An Odin example program from odin-lang/examples: %s.", page.path)
	}
	names := make([dynamic]string, 0, len(packages), context.temp_allocator)
	for pkg in packages {
		append(&names, pkg_import_path(pkg))
	}
	return fmt.tprintf("An Odin example program using %s, from odin-lang/examples: %s.", strings.join(names[:], ", ", context.temp_allocator), page.path)
}

// The documented packages its files import, in order of their import paths
@(private="file")
page_packages :: proc(index: int) -> []^doc.Pkg {
	page := example_pages[index]
	packages := make([dynamic]^doc.Pkg, context.temp_allocator)
	for info, fi in example_files[page.program] {
		if example_page_of[page.program][fi] != index {
			continue
		}
		for pkg in info.packages {
			if !slice.contains(packages[:], pkg) {
				append(&packages, pkg)
			}
		}
	}
	slice.sort_by(packages[:], proc(a, b: ^doc.Pkg) -> bool {
		return pkg_import_path(a) < pkg_import_path(b)
	})
	return packages[:]
}

pkg_page_url :: proc(pkg: ^doc.Pkg) -> string {
	collection := cfg.pkg_to_collection[pkg]
	if path := collection.pkg_to_path[pkg]; path != "" {
		return fmt.tprintf("%s/%s/", collection.base_url, path)
	}
	return fmt.tprintf("%s/", collection.base_url)
}

Example_File_Kind :: enum {
	Shader,
	Build,   // scripts and web pages, only linked to
	Licence, // listed with the assets
	Other,
}

@(private="file")
file_kind :: proc(name: string) -> Example_File_Kind {
	base := strings.to_lower(slashpath.base(name), context.temp_allocator)
	if strings.contains(base, "license") || strings.contains(base, "licence") || strings.has_prefix(base, "copying") || strings.has_suffix(base, "_ofl.txt") {
		return .Licence
	}
	if base == "makefile" {
		return .Build
	}
	switch slashpath.ext(base) {
	case ".vs", ".fs", ".vert", ".frag", ".comp", ".geom", ".tesc", ".tese", ".glsl", ".hlsl", ".metal", ".wgsl":
		return .Shader
	case ".bat", ".cmd", ".sh", ".ps1", ".html", ".htm", ".js", ".mjs":
		return .Build
	}
	return .Other
}

@(private="file")
file_language :: proc(name: string) -> string {
	// of those odin-lang.org's highlight.js has
	switch strings.to_lower(slashpath.ext(name), context.temp_allocator) {
	case ".metal":
		return "cpp"
	case ".wgsl":
		return "rust"
	case ".vs", ".fs", ".vert", ".frag", ".comp", ".geom", ".tesc", ".tese", ".glsl", ".hlsl", ".c", ".h", ".rc":
		return "c"
	case ".json":
		return "json"
	case ".xml", ".manifest", ".html", ".htm":
		return "xml"
	case ".lua":
		return "lua"
	case ".ini", ".toml":
		return "ini"
	case ".yml", ".yaml":
		return "yaml"
	case ".css":
		return "css"
	case ".md":
		return "markdown"
	}
	return "plaintext"
}

@(private="file")
is_build_product :: proc(name: string) -> bool {
	switch strings.to_lower(slashpath.ext(name), context.temp_allocator) {
	case ".dll", ".so", ".dylib", ".lib", ".a", ".o", ".obj", ".exe", ".pdb", ".exp", ".ilk", ".spv", ".wasm":
		return true
	}
	return false
}

@(private="file")
is_image :: proc(name: string) -> bool {
	switch strings.to_lower(slashpath.ext(name), context.temp_allocator) {
	case ".png", ".jpg", ".jpeg", ".gif", ".webp":
		return true
	}
	return false
}

@(private="file")
line_count :: proc(text: string) -> int {
	n := strings.count(text, "\n")
	if text != "" && !strings.has_suffix(text, "\n") {
		n += 1
	}
	return n
}

@(private="file")
file_id :: proc(name: string) -> string {
	id, _ := strings.replace_all(name, " ", "-", context.temp_allocator)
	return id
}

@(private="file")
Page_Files :: struct {
	odin:       [dynamic]int, // of the program's files, the one with `main` first
	shaders:    [dynamic]int, // of its other files
	shown:      [dynamic]int,
	long:       [dynamic]int,
	build:      [dynamic]int,
	assets:     [dynamic]be.Example_Asset, // its licence texts too
	screenshot: int,                       // of its assets, or -1
}

@(private="file")
page_files :: proc(index: int) -> (files: Page_Files) {
	page := example_pages[index]
	program := examples.programs[page.program]
	files.screenshot = -1

	// a file of a folder of programs that are each a file has what its code names, and its screenshot
	source, stem: string
	if page.file >= 0 {
		append(&files.odin, page.file)
		source = program.files[page.file].source
		stem = strings.trim_suffix(program.files[page.file].name, ".odin")
	} else {
		for main in ([]bool{true, false}) {
			for info, fi in example_files[page.program] {
				if info.main == main && example_page_of[page.program][fi] == index {
					append(&files.odin, fi)
				}
			}
		}
	}
	named :: proc(source, name: string) -> bool {
		return source == "" || strings.contains(source, name) || strings.contains(source, slashpath.base(name))
	}

	for file, i in program.other {
		if !named(source, file.name) {
			continue
		}
		switch file_kind(file.name) {
		case .Shader:
			append(&files.shaders, i)
		case .Build:
			append(&files.build, i)
		case .Licence:
			append(&files.assets, be.Example_Asset{file.name, i64(len(file.source))})
		case .Other:
			if file.truncated || line_count(file.source) > EXAMPLE_SHOWN_MAX_LINES {
				append(&files.long, i)
			} else {
				append(&files.shown, i)
			}
		}
	}
	for asset, i in program.assets {
		if is_build_product(asset.name) {
			continue
		}
		asset_stem := strings.trim_suffix(slashpath.base(asset.name), slashpath.ext(asset.name))
		if stem != "" && files.screenshot < 0 && is_image(asset.name) && asset_stem == stem {
			files.screenshot = i
			continue
		}
		// the folder's own, not its examples' screenshots, which their pages show
		is_member_screenshot := false
		for member in page.members {
			if is_image(asset.name) && asset_stem == strings.trim_suffix(program.files[example_pages[member].file].name, ".odin") {
				is_member_screenshot = true
			}
		}
		if !is_member_screenshot && named(source, asset.name) {
			append(&files.assets, asset)
		}
	}
	slice.sort_by(files.assets[:], proc(a, b: be.Example_Asset) -> bool {
		return a.name < b.name
	})
	return
}

@(private="file")
Toc_Item :: struct {
	id, text: string,
	count:    int, // shown when more than 0
	level:    int, // 0 for a section, 1 for a file, 2 for a procedure
}

@(private="file")
write_example_page :: proc(w: io.Writer, index: int) {
	context.allocator = context.temp_allocator
	page := example_pages[index]
	program := examples.programs[page.program]
	files := page_files(index)
	toc: [dynamic]Toc_Item

	fmt.wprintln(w, `<div class="row odin-main odin-docs-layout my-4">`)
	defer fmt.wprintln(w, `</div>`)

	write_examples_sidebar(w, index)

	fmt.wprintln(w, `<article class="col-lg-8 p-4 documentation odin-article">`)

	// examples / raylib / ports / core / core_basic_window
	fmt.wprintln(w, `<nav class="pkg-breadcrumb" aria-label="breadcrumb">`)
	io.write_string(w, "<ol class=\"breadcrumb\">\n")
	fmt.wprintf(w, "<li class=\"breadcrumb-item\"><a href=\"%s/\">examples</a></li>\n", EXAMPLES_URL)
	parts := strings.split(page.path, "/")
	for part, i in parts {
		path := strings.join(parts[:i+1], "/")
		if i+1 == len(parts) {
			fmt.wprintf(w, "<li class=\"breadcrumb-item active\" aria-current=\"page\">%s</li>\n", part)
		} else if at, ok := example_page_at[path]; ok {
			fmt.wprintf(w, "<li class=\"breadcrumb-item\"><a href=\"%s\">%s</a></li>\n", example_url(at), part)
		} else {
			fmt.wprintf(w, "<li class=\"breadcrumb-item\">%s</li>\n", part)
		}
	}
	io.write_string(w, "</ol>\n")
	fmt.wprintln(w, `</nav>`)

	source_path := program.path
	source_url := example_github_url(program.path, "tree")
	if page.file >= 0 {
		source_path = fmt.tprintf("%s/%s", program.path, program.files[page.file].name)
		source_url = example_github_url(source_path)
	}
	fmt.wprintf(w, "<h1>%s", page.path)
	write_example_platforms(w, index)
	fmt.wprintf(w, "<div class=\"doc-source\"><a href=\"%s\"><em>Source</em></a></div></h1>\n", source_url)

	// before anything else, as it isn't under Odin's licence
	if program.license.path != "" {
		write_example_licence(w, program.license)
	}

	repo_name := strings.trim_prefix(strings.trim_prefix(examples.repo, "https://"), "github.com/")
	fmt.wprintln(w, `<ul class="odin-collection-meta odin-pkg-meta">`)
	fmt.wprintf(w, `<li><span>Source</span> <a href="%s">%s/%s</a></li>`+"\n", source_url, repo_name, escape_html_text(source_path))
	if packages := page_packages(index); len(packages) > 0 {
		io.write_string(w, `<li><span>Packages</span> `)
		for pkg, i in packages {
			if i > 0 {
				io.write_string(w, ", ")
			}
			fmt.wprintf(w, `<a href="%s">%s</a>`, pkg_page_url(pkg), pkg_import_path(pkg))
		}
		io.write_string(w, "</li>\n")
	}
	if page.file >= 0 {
		folder := example_page_at[program.path]
		fmt.wprintf(w, `<li><span>Part of</span> <a href="%s">%s</a></li>`+"\n", example_url(folder), program.path)
	}
	if len(page.members) > 0 {
		fmt.wprintf(w, `<li><span>Examples</span> %d</li>`+"\n", len(page.members))
	}
	if page.file < 0 && len(files.odin) > 0 {
		io.write_string(w, `<li><span>Files</span> `)
		for fi, i in files.odin {
			if i > 0 {
				io.write_string(w, ", ")
			}
			name := program.files[fi].name
			fmt.wprintf(w, `<a href="#%s">%s</a>`, name, name)
		}
		io.write_string(w, "</li>\n")
	}
	fmt.wprintln(w, `</ul>`)

	if files.screenshot >= 0 {
		asset := program.assets[files.screenshot]
		if src, shown := github_image_url(example_github_url(fmt.tprintf("%s/%s", program.path, asset.name))); shown {
			fmt.wprintf(w, `<img class="example-screenshot" src="%s" alt="A screenshot of %s" loading="lazy">`+"\n", src, slashpath.base(page.path))
		}
	}

	fmt.wprintln(w, `<section class="documentation">`)

	if page.file < 0 && program.readme != "" {
		fmt.wprintln(w, "<h2>Overview</h2>")
		fmt.wprintln(w, `<div id="pkg-overview">`)
		ctx := Doc_Context{owner = page.path, readme_base = example_github_url(fmt.tprintf("%s/", program.path))}
		io.write_string(w, render_markdown(program.readme, &ctx, context.temp_allocator))
		fmt.wprintln(w, "</div>")
		append(&toc, Toc_Item{id = "pkg-overview", text = "Overview"})
	}

	if len(page.members) > 0 {
		fmt.wprintf(w, `<h2 id="example-examples">Examples <span class="pkg-count">%d</span></h2>`+"\n", len(page.members))
		fmt.wprintln(w, `<table class="odin-pkg-table example-members">`)
		for member in page.members {
			io.write_string(w, `<tbody><tr><td class="pkg-name">`)
			write_example_link_open(w, member)
			write_breakable_path(w, slashpath.base(example_pages[member].path))
			io.write_string(w, "</a>")
			write_example_platforms(w, member)
			fmt.wprintf(w, "</td><td class=\"pkg-desc\">%s</td></tr></tbody>\n", escape_html_text(example_summary(member)))
		}
		fmt.wprintln(w, `</table>`)
		append(&toc, Toc_Item{id = "example-examples", text = "Examples", count = len(page.members)})
	}

	file_heading :: proc(w: io.Writer, name, build: string, lines: int, url: string) {
		id := file_id(name)
		fmt.wprintf(w, `<h3 id="%s"><span><a class="doc-id-link" href="#%s">%s<span class="a-hidden">&nbsp;¶</span></a>`, id, id, escape_html_text(name))
		if build != "" {
			fmt.wprintf(w, ` <span class="doc-badge" title="#+build %s">%s</span>`, build, build)
		}
		// whether to wrap its long lines and the tab width to show it with, which every file here shares
		io.write_string(w, `</span><div class="doc-source"><label class="example-wrap"><input type="checkbox" autocomplete="off">Wrap lines</label>`)
		io.write_string(w, `<label class="example-tab-width">Tab width <select autocomplete="off">`)
		for n in 1..=8 {
			fmt.wprintf(w, `<option%s>%d</option>`, " selected" if n == EXAMPLE_TAB_WIDTH else "", n)
		}
		fmt.wprintf(w, `</select></label><span class="example-lines">%s line%s</span><a href="%s"><em>Source</em></a></div></h3>`+"\n",
		            thousands(lines), "" if lines == 1 else "s", url)
	}
	file_url :: proc(program: be.Example_Program, name: string) -> string {
		return example_github_url(fmt.tprintf("%s/%s", program.path, name))
	}
	write_links :: proc(w: io.Writer, program: be.Example_Program, others: []int) {
		fmt.wprintln(w, `<ul class="example-links">`)
		for i in others {
			file := program.other[i]
			lines := line_count(file.source)
			// only its start is in the bundle, which may be one long line
			size := fmt.tprintf("over %d KB", len(file.source) / 1024) if file.truncated else fmt.tprintf("%s line%s", thousands(lines), "" if lines == 1 else "s")
			fmt.wprintf(w, `<li><a href="%s">%s</a> <span class="example-lines">%s</span></li>`+"\n", file_url(program, file.name), escape_html_text(file.name), size)
		}
		fmt.wprintln(w, `</ul>`)
	}
	write_text :: proc(w: io.Writer, program: be.Example_Program, others: []int, toc: ^[dynamic]Toc_Item) {
		for i in others {
			file := program.other[i]
			fmt.wprintln(w, `<div class="example-file">`)
			file_heading(w, file.name, "", line_count(file.source), file_url(program, file.name))
			fmt.wprintf(w, `<pre class="doc-example-code example-code"><code class="language-%s">%s</code></pre>`+"\n", file_language(file.name), escape_html_text(file.source))
			if file.truncated {
				fmt.wprintf(w, `<p class="example-note">Only its start; <a href="%s">the rest is on GitHub</a>.</p>`+"\n", file_url(program, file.name))
			}
			fmt.wprintln(w, `</div>`)
			append(toc, Toc_Item{id = file_id(file.name), text = escape_html_text(file.name), level = 1})
		}
	}

	if len(files.odin) > 0 {
		fmt.wprintln(w, `<h2 id="example-code">Code</h2>`)
		append(&toc, Toc_Item{id = "example-code", text = "Code"})
		for fi in files.odin {
			file := program.files[fi]
			info := example_files[page.program][fi]
			fmt.wprintln(w, `<div class="example-file">`)
			file_heading(w, file.name, info.build, line_count(file.source), file_url(program, file.name))
			io.write_string(w, `<pre class="doc-example-code example-code"><code class="hljs nohighlight">`)
			for line, i in example_html_lines(page.program, fi) {
				fmt.wprintf(w, `<span class="line" id="{0:s}-L{1:d}"><a class="ln" href="#{0:s}-L{1:d}">{1:d}</a><span class="line-text">{2:s}</span></span>`+"\n", file.name, i+1, line)
			}
			io.write_string(w, "</code></pre>\n")
			fmt.wprintln(w, `</div>`)
			append(&toc, Toc_Item{id = file.name, text = file.name, level = 1})
			for p in info.procs {
				append(&toc, Toc_Item{id = fmt.tprintf("%s-L%d", file.name, p.line), text = p.name, level = 2})
			}
		}
	}

	if len(files.shaders) > 0 {
		fmt.wprintln(w, `<h2 id="example-shaders">Shaders</h2>`)
		append(&toc, Toc_Item{id = "example-shaders", text = "Shaders"})
		write_text(w, program, files.shaders[:], &toc)
	}

	if len(files.shown) + len(files.long) > 0 {
		fmt.wprintln(w, `<h2 id="example-other-files">Other Files</h2>`)
		append(&toc, Toc_Item{id = "example-other-files", text = "Other Files"})
		write_text(w, program, files.shown[:], &toc)
		if len(files.long) > 0 {
			write_links(w, program, files.long[:])
		}
	}

	if len(files.build) > 0 {
		fmt.wprintf(w, `<h2 id="example-build">To Build and Run <span class="pkg-count">%d</span></h2>`+"\n", len(files.build))
		append(&toc, Toc_Item{id = "example-build", text = "To Build and Run", count = len(files.build)})
		write_links(w, program, files.build[:])
	}

	if len(files.assets) > 0 {
		fmt.wprintf(w, `<h2 id="example-assets">Assets <span class="pkg-count">%d</span></h2>`+"\n", len(files.assets))
		append(&toc, Toc_Item{id = "example-assets", text = "Assets", count = len(files.assets)})
		fmt.wprintln(w, `<ul class="example-assets">`)
		for asset in files.assets {
			fmt.wprintf(w, `<li><a href="%s">%s</a></li>`+"\n", file_url(program, asset.name), escape_html_text(asset.name))
		}
		fmt.wprintln(w, `</ul>`)
	}

	// what it uses of each package, linked to its docs
	used := make(map[^doc.Pkg][dynamic]string)
	for info, fi in example_files[page.program] {
		if example_page_of[page.program][fi] != index {
			continue
		}
		for u in info.used {
			names := used[u.pkg]
			if !slice.contains(names[:], u.name) {
				append(&names, u.name)
			}
			used[u.pkg] = names
		}
	}
	if len(used) > 0 {
		total := 0
		for _, names in used {
			total += len(names)
		}
		fmt.wprintf(w, `<h2 id="example-declarations">Declarations Used <span class="pkg-count">%d</span></h2>`+"\n", total)
		append(&toc, Toc_Item{id = "example-declarations", text = "Declarations Used", count = total})
		packages := make([dynamic]^doc.Pkg)
		for pkg in used {
			append(&packages, pkg)
		}
		slice.sort_by(packages[:], proc(a, b: ^doc.Pkg) -> bool {
			return pkg_import_path(a) < pkg_import_path(b)
		})
		fmt.wprintln(w, `<ul class="example-used">`)
		for pkg in packages {
			names := used[pkg]
			slice.sort_by(names[:], proc(a, b: string) -> bool {
				return strings.to_lower(a) < strings.to_lower(b)
			})
			fmt.wprintf(w, `<li><a class="example-used-pkg" href="%s">%s</a> `, pkg_page_url(pkg), pkg_import_path(pkg))
			for name, i in names {
				if i > 0 {
					io.write_string(w, " · ")
				}
				fmt.wprintf(w, `<a href="%s">%s</a>`, doc_entity_url(pkg, name), name)
			}
			io.write_string(w, "</li>\n")
		}
		fmt.wprintln(w, `</ul>`)
	}

	fmt.wprintln(w, "</section>")
	fmt.wprintln(w, `</article>`)

	write_items :: proc(w: io.Writer, items: []Toc_Item) {
		for i := 0; i < len(items); {
			item := items[i]
			j := i + 1
			for j < len(items) && items[j].level > item.level {
				j += 1
			}
			// a file breaks as a path does, and a procedure at its `_`s, as the package pages' names do
			fmt.wprintf(w, `<li><a href="#%s">`, item.id)
			switch item.level {
			case 0:  io.write_string(w, item.text)
			case 1:  write_breakable_path(w, item.text)
			case:    write_breakable_name(w, item.text)
			}
			if item.count > 0 {
				fmt.wprintf(w, `<span class="toc-count">%d</span>`, item.count)
			}
			io.write_string(w, "</a>")
			if j > i + 1 {
				io.write_string(w, "<ul>\n")
				write_items(w, items[i+1:j])
				io.write_string(w, "</ul>")
			}
			io.write_string(w, "</li>\n")
			i = j
		}
	}
	fmt.wprintln(w, `<div class="col-lg-2 odin-toc-border navbar-light"><div class="sticky-top odin-below-navbar py-3">`)
	write_sidebar_toggle(w, "toc-sidebar", "Contents")
	fmt.wprintln(w, `<nav id="TableOfContents">`)
	fmt.wprintln(w, `<ul>`)
	write_items(w, toc[:])
	fmt.wprintln(w, `</ul>`)
	fmt.wprintln(w, `</nav>`)
	fmt.wprintln(w, `</div></div>`)
}

@(private="file")
write_example_licence :: proc(w: io.Writer, license: be.Example_License) {
	// all of a short one; of a long one, up to its copyright line, then the rest when asked for, but always on the page
	MAX_SHOWN_LINES :: 6
	lines := strings.split_lines(strings.trim_space(license.text), context.temp_allocator)
	shown := len(lines)
	if shown > MAX_SHOWN_LINES {
		// or else its first paragraph
		shown = 0
		for line, i in lines[:MAX_SHOWN_LINES] {
			if strings.contains(strings.to_lower(line, context.temp_allocator), "copyright") || strings.contains(line, "©") {
				shown = i + 1
				break
			}
		}
		if shown == 0 {
			for shown < MAX_SHOWN_LINES && strings.trim_space(lines[shown]) != "" {
				shown += 1
			}
		}
	}

	write_text :: proc(w: io.Writer, lines: []string) {
		// its addresses linked
		text := strings.trim_space(strings.join(lines, "\n", context.temp_allocator))
		for text != "" {
			start := strings.index(text, "https://")
			if http := strings.index(text, "http://"); http >= 0 && (start < 0 || http < start) {
				start = http
			}
			if start < 0 {
				io.write_string(w, escape_html_text(text))
				break
			}
			io.write_string(w, escape_html_text(text[:start]))
			end := start
			for end < len(text) && !strings.is_space(rune(text[end])) {
				end += 1
			}
			url := strings.trim_right(text[start:end], ".,;:)")
			fmt.wprintf(w, `<a href="{0:s}">{0:s}</a>`, escape_html_text(url))
			text = text[start+len(url):]
		}
	}

	fmt.wprintln(w, `<div class="example-licence" id="example-licence">`)
	fmt.wprintf(w, `<div class="example-licence-head"><span>Licence</span> This example has its own licence, rather than Odin's: <a href="%s">%s</a></div>`+"\n",
	            example_github_url(license.path), escape_html_text(license.path))
	io.write_string(w, `<div class="example-licence-text">`)
	write_text(w, lines[:shown])
	io.write_string(w, "</div>\n")
	if shown < len(lines) {
		io.write_string(w, `<details class="example-licence-rest"><summary>The rest of the licence</summary><div class="example-licence-text">`)
		write_text(w, lines[shown:])
		io.write_string(w, "</div></details>\n")
	}
	fmt.wprintln(w, `</div>`)
}

@(private="file")
write_examples_sidebar :: proc(w: io.Writer, current: int) {
	fmt.wprintln(w, `<nav id="pkg-sidebar" class="col-lg-2 odin-sidebar-border navbar-light sticky-top odin-below-navbar">`)
	defer fmt.wprintln(w, `</nav>`)
	write_sidebar_toggle(w, "pkg-sidebar", "Examples")
	fmt.wprintln(w, `<div class="odin-sidebar-content pb-3">`)
	defer fmt.wprintln(w, `</div>`)
	fmt.wprintf(w, "<h4 class=\"pkg-sidebar-title\"><a style=\"color: inherit;\" href=\"%s/\">Examples</a></h4>\n", EXAMPLES_URL)

	write_node :: proc(w: io.Writer, node: ^Example_Node, current: int, top: bool) {
		label, n := example_node_label(node)
		switch {
		case !top:                 io.write_string(w, `<li>`)
		case len(n.children) > 0:  io.write_string(w, `<li class="nav-item pkg-sidebar-group">`)
		case:                      io.write_string(w, `<li class="nav-item">`)
		}
		if n.page >= 0 {
			fmt.wprintf(w, `<a%s href="%s">`, ` class="active"` if n.page == current else "", example_url(n.page))
			write_breakable_path(w, label)
			io.write_string(w, `</a>`)
		} else {
			io.write_string(w, `<span class="pkg-sidebar-label">`)
			write_breakable_path(w, label)
			io.write_string(w, `</span>`)
		}
		if len(n.children) > 0 {
			io.write_string(w, "<ul>\n")
			for child in n.children {
				write_node(w, child, current, false)
			}
			io.write_string(w, "</ul>")
		}
		io.write_string(w, "</li>\n")
	}

	pages := make([dynamic]int, 0, len(example_pages), context.temp_allocator)
	for _, i in example_pages {
		append(&pages, i)
	}
	fmt.wprintln(w, `<ul>`)
	for child in example_tree(pages[:]).children {
		write_node(w, child, current, true)
	}
	fmt.wprintln(w, `</ul>`)
}

@(private="file")
write_examples_index :: proc(w: io.Writer) {
	context.allocator = context.temp_allocator

	// the packages each is about, as their External Examples list it
	about := make(map[int][dynamic]^doc.Pkg)
	for pkg, by_name in example_uses {
		for _, uses in by_name {
			for use in uses {
				page := example_page_of[use.program][use.file]
				pkgs := about[page]
				if !slice.contains(pkgs[:], pkg) {
					append(&pkgs, pkg)
				}
				about[page] = pkgs
			}
		}
	}

	fmt.wprintln(w, `<div class="row odin-main odin-docs-layout my-4">`)
	defer fmt.wprintln(w, `</div>`)
	write_examples_sidebar(w, -1)
	fmt.wprintln(w, `<article class="col-lg-10 p-4">`)
	defer fmt.wprintln(w, `</article>`)

	repo_name := strings.trim_prefix(strings.trim_prefix(examples.repo, "https://"), "github.com/")
	fmt.wprintln(w, `<header class="odin-collection-header">`)
	fmt.wprintln(w, "<h1>Examples</h1>")
	fmt.wprintf(w, `<p class="odin-collection-lead">Example programs from <a href="%s">%s</a>, with the names in their code linked to their documentation.</p>`+"\n", examples.repo, repo_name)
	fmt.wprintln(w, `<ul class="odin-collection-meta">`)
	fmt.wprintf(w, `<li><span>Source</span> <a href="%s">%s</a></li>`+"\n", examples.repo, repo_name)
	fmt.wprintf(w, `<li><span>Commit</span> <a href="%s/tree/%s"><code>%s</code></a></li>`+"\n", examples.repo, examples.commit, examples.commit[:min(7, len(examples.commit))])
	fmt.wprintf(w, `<li><span>Examples</span> %d</li>`+"\n", len(example_pages))
	fmt.wprintln(w, `</ul>`)
	fmt.wprintln(w, `</header>`)

	fmt.wprintf(w, `<h2 class="odin-pkg-list-title">Examples <span class="pkg-count">%d</span></h2>`+"\n", len(example_pages))
	fmt.wprintln(w, `<table class="odin-pkg-table example-index">`)
	defer fmt.wprintln(w, `</table>`)

	write_desc :: proc(w: io.Writer, page: int, about: map[int][dynamic]^doc.Pkg) {
		io.write_string(w, `<td class="pkg-desc">`)
		io.write_string(w, escape_html_text(example_summary(page)))
		if pkgs, ok := about[page]; ok {
			slice.sort_by(pkgs[:], proc(a, b: ^doc.Pkg) -> bool {
				return pkg_import_path(a) < pkg_import_path(b)
			})
			io.write_string(w, ` <span class="example-about">`)
			for pkg, i in pkgs {
				if i > 0 {
					io.write_string(w, ", ")
				}
				fmt.wprintf(w, `<a href="%s">%s</a>`, pkg_page_url(pkg), pkg_import_path(pkg))
			}
			io.write_string(w, `</span>`)
		}
		io.write_string(w, `</td>`)
	}
	under :: proc(node: ^Example_Node, pages: ^[dynamic]int) {
		for child in node.children {
			if child.page >= 0 {
				append(pages, child.page)
			}
			under(child, pages)
		}
	}

	pages := make([dynamic]int, 0, len(example_pages))
	for _, i in example_pages {
		append(&pages, i)
	}
	for top in example_tree(pages[:]).children {
		below := make([dynamic]int)
		under(top, &below)
		if len(below) == 0 {
			io.write_string(w, `<tbody><tr><td class="pkg-name">`)
			write_example_link_open(w, top.page)
			fmt.wprintf(w, "%s</a>", top.name)
			write_example_platforms(w, top.page)
			io.write_string(w, "</td>")
			write_desc(w, top.page, about)
			io.write_string(w, "</tr></tbody>\n")
			continue
		}
		io.write_string(w, `<tbody class="pkg-group"><tr class="pkg-group-head"><td class="pkg-name">`)
		if top.page >= 0 {
			write_example_link_open(w, top.page)
			fmt.wprintf(w, "%s</a>", top.name)
			write_example_platforms(w, top.page)
			io.write_string(w, "</td>")
			write_desc(w, top.page, about)
		} else {
			fmt.wprintf(w, `<span class="pkg-group-label">%s</span></td><td class="pkg-desc"><span class="pkg-count">%d example%s</span></td>`, top.name, len(below), "" if len(below) == 1 else "s")
		}
		io.write_string(w, "</tr>\n")
		for page in below {
			io.write_string(w, `<tr class="pkg-child"><td class="pkg-name">`)
			write_example_link_open(w, page)
			write_breakable_path(w, example_pages[page].path[len(top.name)+1:])
			io.write_string(w, `</a>`)
			write_example_platforms(w, page)
			io.write_string(w, `</td>`)
			write_desc(w, page, about)
			io.write_string(w, "</tr>\n")
		}
		io.write_string(w, "</tbody>\n")
	}
}
