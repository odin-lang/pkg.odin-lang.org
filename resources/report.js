"use strict";

(async () => {
	const report = document.getElementById("odin-report");
	if (!report) {
		return;
	}

	let data;
	try {
		const response = await fetch("/report/data.json");
		data = await response.json();
	} catch {
		report.insertAdjacentHTML("beforeend", `<p>The report's data couldn't be loaded.</p>`);
		return;
	}

	const CATEGORIES = [
		{key: "links",    label: "Links",      kinds: ["link", "stale"],     badge: "kind-t",   none: "Every link and name resolves."},
		{key: "params",   label: "Parameters", kinds: ["param", "missing"],  badge: "kind-p",   none: "Every Inputs and Returns list matches its signature."},
		{key: "examples", label: "Examples",   kinds: ["example", "output"], badge: "kind-c",   none: "Every example parses."},
		{key: "overview", label: "Overviews",  kinds: [],                    badge: "kind-pkg", none: "Every package has an overview."},
	];
	const DECL_KINDS = {t: "Types", c: "Constants", v: "Variables", p: "Procedures", g: "Procedure groups"};
	const SIZES = {
		total:    {label: "Declarations", of: n => n.total},
		undoc:    {label: "Undocumented", of: n => n.undoc},
		problems: {label: "Problems",     of: n => n.problems},
	};
	const category_of = kind => CATEGORIES.find(c => c.kinds.includes(kind));

	const escape = s => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
	const with_code = s => escape(s).replace(/`([^`]+)`/g, "<code>$1</code>");
	const count = n => n.toLocaleString("en-US");
	const plural = (n, one, many = one + "s") => `${count(n)} ${n === 1 ? one : many}`;
	const coverage_of = n => n.total ? (n.total - n.undoc) / n.total : null;
	// never "100%" while something is missing, nor "0%" once something is there
	const percent = c => c === null ? "nothing declared" : `${c >= 1 ? 100 : c <= 0 ? 0 : Math.min(99, Math.max(1, Math.round(c * 100)))}%`;

	// Packages, and the directories holding them

	const make_node = (name, path, parent) => ({
		name, path, parent, children: [], pkg: null, self: null,
		total: 0, undoc: 0, problems: 0, packages: 0,
		counts: {links: 0, params: 0, examples: 0, overview: 0},
	});
	const add_stats = (to, from) => {
		to.total    += from.total;
		to.undoc    += from.undoc;
		to.problems += from.problems;
		to.packages += from.packages;
		for (const key in to.counts) {
			to.counts[key] += from.counts[key];
		}
	};

	const root = make_node("All", "", null);
	const nodes = new Map([["", root]]);
	const pkg_by_import = new Map();
	for (const p of data.packages) {
		p.total = Object.values(p.declared).reduce((a, b) => a + b, 0);
		p.undoc = Object.values(p.undocumented).reduce((a, l) => a + l.length, 0);
		p.counts = {links: 0, params: 0, examples: 0, overview: p.overview ? 0 : 1};
		for (const [kind] of p.issues) {
			p.counts[category_of(kind).key] += 1;
		}
		p.problems = p.issues.length + p.counts.overview;
		p.packages = 1;
		pkg_by_import.set(p.import, p);

		let node = root;
		const parts = p.path.split("/");
		parts.forEach((part, i) => {
			const path = parts.slice(0, i + 1).join("/");
			let child = nodes.get(path);
			if (!child) {
				child = make_node(part, path, node);
				node.children.push(child);
				nodes.set(path, child);
			}
			node = child;
		});
		node.pkg = p;
		p.node = node;
	}
	const aggregate = node => {
		if (node.pkg) {
			// a package with packages inside has a tile of its own among them
			node.self = make_node(node.name, node.path + "/", node);
			node.self.pkg = node.pkg;
			node.self.is_self = true;
			add_stats(node.self, node.pkg);
			add_stats(node, node.pkg);
		}
		for (const child of node.children) {
			aggregate(child);
			add_stats(node, child);
		}
	};
	aggregate(root);

	const title_of = node => {
		if (node === root) {
			return "All packages";
		}
		if (node.pkg && node.children.length === 0) {
			return node.pkg.import;
		}
		const [collection, ...rest] = node.path.split("/");
		return rest.length ? `${collection}:${rest.join("/")}/` : `${collection}:`;
	};
	const is_inside = (node, ancestor) => {
		for (let n = node; n; n = n.parent) {
			if (n === ancestor) {
				return true;
			}
		}
		return false;
	};

	// The page around the map

	const all_problems = CATEGORIES.map(c => root.counts[c.key]).reduce((a, b) => a + b, 0);
	report.insertAdjacentHTML("beforeend", `
		<div class="odin-report-stats">
			<div><b>${count(data.packages.length)}</b> packages</div>
			<div><b>${count(root.total)}</b> declarations</div>
			<div><b>${percent(coverage_of(root))}</b> documented</div>
			<div><b>${count(all_problems)}</b> problems:
				${CATEGORIES.map(c => `<a class="odin-report-badge ${c.badge}" href="#=${c.key}">${c.label} ${count(root.counts[c.key])}</a>`).join(" ")}
			</div>
			<div class="odin-report-generated">Generated ${escape(data.generated)}</div>
		</div>
		<div class="odin-report-toolbar">
			<nav class="odin-report-crumbs" aria-label="Where the map is"></nav>
			<div class="odin-report-controls">
				<input type="search" class="odin-report-find" list="odin-report-find-list" placeholder="Find a package…" aria-label="Find a package" spellcheck="false" autocomplete="off">
				<datalist id="odin-report-find-list">${[...pkg_by_import.keys()].sort().map(i => `<option value="${escape(i)}">`).join("")}</datalist>
				<div class="odin-report-size" role="group" aria-label="Size the map by">
					<span>Size</span>
					${Object.entries(SIZES).map(([key, s]) => `<button type="button" data-size="${key}">${s.label}</button>`).join("")}
				</div>
			</div>
		</div>
		<div class="odin-report-main">
			<div class="odin-report-map">
				<canvas tabindex="0" aria-label="Map of the packages: the bigger a box, the more it holds; the greener, the more of it is documented. Arrow keys move between packages, Escape goes up a level."></canvas>
				<div class="odin-report-tip" hidden></div>
			</div>
			<aside class="odin-report-panel" aria-live="polite"></aside>
		</div>
		<div class="odin-report-legend">
			<span>0%</span><span class="odin-report-scale"></span><span>100% documented</span>
			<span class="odin-report-badge kind-c">3</span><span>problems</span>
			<span class="odin-report-hint">Click a package for its details, a directory to zoom in · arrow keys move · Esc goes up a level</span>
		</div>
	`);

	const canvas = report.querySelector("canvas");
	const map    = report.querySelector(".odin-report-map");
	const tip    = report.querySelector(".odin-report-tip");
	const panel  = report.querySelector(".odin-report-panel");
	const crumbs = report.querySelector(".odin-report-crumbs");
	const find   = report.querySelector(".odin-report-find");
	const ctx    = canvas.getContext("2d");

	const state = {zoom: root, selected: null, view: "group", category: null, size: "total", hover: null};
	try {
		state.size = SIZES[localStorage.getItem("odin-report-size")] ? localStorage.getItem("odin-report-size") : "total";
	} catch {
	}

	// Colours, from the page's own theme

	const has_oklch = typeof CSS !== "undefined" && CSS.supports && CSS.supports("color", "oklch(0.5 0.1 100)");
	let theme = null;
	const read_theme = () => {
		const dark = document.body.classList.contains("dark-mode") || document.documentElement.classList.contains("dark-mode");
		const style = getComputedStyle(report);
		const body = getComputedStyle(document.body);
		const variable = name => style.getPropertyValue(name).trim();
		let bg = body.backgroundColor;
		if (!bg || bg === "transparent" || bg === "rgba(0, 0, 0, 0)") {
			bg = dark ? "#0d1117" : "#ffffff";
		}
		theme = {
			dark, bg,
			text:   body.color,
			muted:  variable("--odin-sidebar-muted") || "#6c757d",
			border: variable("--odin-card-border") || "#dee2e6",
			link:   variable("--odin-sidebar-link") || "#3882d2",
			font:   body.fontFamily,
			frame:  dark ? "rgba(255, 255, 255, 0.035)" : "rgba(0, 0, 0, 0.03)",
			badge_bg:   dark ? "rgba(243, 154, 94, 0.18)" : "rgba(184, 83, 14, 0.12)",
			badge_text: dark ? "#f39a5e" : "#b8530e",
		};
		report.querySelector(".odin-report-scale").style.background =
			`linear-gradient(to right, ${[0, 0.25, 0.5, 0.75, 1].map(fill_for).join(", ")})`;
	};
	const fill_for = coverage => {
		if (coverage === null) {
			return theme.dark ? "rgba(127, 127, 127, 0.2)" : "rgba(127, 127, 127, 0.14)";
		}
		if (has_oklch) {
			const hue = 25 + 120 * coverage;
			return theme.dark ? `oklch(0.42 0.09 ${hue})` : `oklch(0.87 0.08 ${hue})`;
		}
		const hue = 120 * coverage;
		return theme.dark ? `hsl(${hue} 35% 28%)` : `hsl(${hue} 60% 84%)`;
	};

	// Layout: squarified treemaps, nested by directory

	const HEADER = 22, PAD = 3, GAP = 1;
	let width = 0, height = 0;

	const weights = new Map();
	const weight_of = node => {
		if (weights.has(node)) {
			return weights.get(node);
		}
		let w = 0;
		if (node.children.length === 0) {
			// square roots, so the small packages still show beside the thousands-strong ones
			w = Math.sqrt(SIZES[state.size].of(node));
		} else {
			if (node.self) {
				w += weight_of(node.self);
			}
			for (const child of node.children) {
				w += weight_of(child);
			}
		}
		weights.set(node, w);
		return w;
	};
	const items_of = node => {
		const items = [];
		for (const child of node.self ? [node.self, ...node.children] : node.children) {
			const w = weight_of(child);
			if (w > 0) {
				items.push({node: child, w});
			}
		}
		return items.sort((a, b) => b.w - a.w);
	};

	const worst = (areas, i, j, side) => {
		let sum = 0, most = 0, least = Infinity;
		for (let k = i; k < j; k++) {
			sum += areas[k];
			most = Math.max(most, areas[k]);
			least = Math.min(least, areas[k]);
		}
		return Math.max(side * side * most / (sum * sum), sum * sum / (side * side * least));
	};
	const squarify = (items, r) => {
		const total = items.reduce((a, it) => a + it.w, 0);
		if (!total || r.w <= 0 || r.h <= 0) {
			items.forEach(it => (it.r = {x: r.x, y: r.y, w: 0, h: 0}));
			return;
		}
		const areas = items.map(it => it.w * r.w * r.h / total);
		let rest = {...r};
		for (let i = 0; i < items.length; /**/) {
			const side = Math.min(rest.w, rest.h);
			let j = i + 1;
			let best = worst(areas, i, j, side);
			while (j < items.length) {
				const next = worst(areas, i, j + 1, side);
				if (next > best) {
					break;
				}
				best = next;
				j += 1;
			}
			let sum = 0;
			for (let k = i; k < j; k++) {
				sum += areas[k];
			}
			if (rest.w >= rest.h) {
				const column = sum / rest.h;
				let y = rest.y;
				for (let k = i; k < j; k++) {
					const h = areas[k] / column;
					items[k].r = {x: rest.x, y, w: column, h};
					y += h;
				}
				rest = {x: rest.x + column, y: rest.y, w: rest.w - column, h: rest.h};
			} else {
				const row = sum / rest.w;
				let x = rest.x;
				for (let k = i; k < j; k++) {
					const w = areas[k] / row;
					items[k].r = {x, y: rest.y, w, h: row};
					x += w;
				}
				rest = {x: rest.x, y: rest.y + row, w: rest.w, h: rest.h - row};
			}
			i = j;
		}
	};

	const build_layout = () => {
		weights.clear();
		const out = [];
		const visit = (node, r, depth) => {
			const is_group = node.children.length > 0;
			// a directory too small to open up shows as one box, zoomed into when clicked
			if (!is_group || r.w < 64 || r.h < 52) {
				out.push({node, r, depth, leaf: true, group: is_group});
				return;
			}
			out.push({node, r, depth, leaf: false, group: true});
			const items = items_of(node);
			squarify(items, {x: r.x + PAD, y: r.y + HEADER, w: r.w - 2 * PAD, h: r.h - HEADER - PAD});
			for (const it of items) {
				visit(it.node, it.r, depth + 1);
			}
		};
		const items = items_of(state.zoom);
		squarify(items, {x: 0, y: 0, w: width, h: height});
		for (const it of items) {
			visit(it.node, it.r, 0);
		}
		return out;
	};

	// Drawing, with zooms animated from where things were to where they go

	let layout = [];
	let shown = new Map(); // path -> the rect drawn last
	let animation = null;
	let frame = 0;

	const ease = t => t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
	const lerp = (a, b, t) => ({x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, w: a.w + (b.w - a.w) * t, h: a.h + (b.h - a.h) * t});

	const relayout = animate => {
		const from = new Map(shown);
		const previous_zoom = animation ? animation.zoom : null;
		layout = build_layout();
		if (animate && !matchMedia("(prefers-reduced-motion: reduce)").matches) {
			if (previous_zoom && previous_zoom !== state.zoom) {
				from.set(previous_zoom.path, {x: 0, y: 0, w: width, h: height});
			}
			for (const item of layout) {
				item.from = null;
				for (let n = item.node; n; n = n.parent) {
					const r = from.get(n.path);
					if (r) {
						item.from = r;
						break;
					}
				}
			}
			animation = {start: performance.now(), zoom: state.zoom};
		} else {
			animation = {start: -Infinity, zoom: state.zoom};
		}
		request_draw();
	};
	const request_draw = () => {
		if (!frame) {
			frame = requestAnimationFrame(draw);
		}
	};

	const fit_text = (text, max) => {
		if (ctx.measureText(text).width <= max) {
			return text;
		}
		let lo = 0, hi = text.length;
		while (lo < hi) {
			const mid = (lo + hi + 1) >> 1;
			if (ctx.measureText(text.slice(0, mid) + "…").width <= max) {
				lo = mid;
			} else {
				hi = mid - 1;
			}
		}
		return lo > 0 ? text.slice(0, lo) + "…" : "";
	};
	const round_rect = (x, y, w, h, radius) => {
		ctx.beginPath();
		if (ctx.roundRect) {
			ctx.roundRect(x, y, w, h, radius);
		} else {
			ctx.rect(x, y, w, h);
		}
	};
	const draw_badge = (text, right, top) => {
		ctx.font = `600 10px ${theme.font}`;
		const w = ctx.measureText(text).width + 10;
		round_rect(right - w, top, w, 15, 7.5);
		ctx.fillStyle = theme.badge_bg;
		ctx.fill();
		ctx.fillStyle = theme.badge_text;
		ctx.fillText(text, right - w + 5, top + 11);
		return w;
	};

	const draw_group = (item, r) => {
		const node = item.node;
		ctx.fillStyle = theme.frame;
		ctx.fillRect(r.x + GAP, r.y + GAP, r.w - 2 * GAP, r.h - 2 * GAP);
		ctx.strokeStyle = state.hover === item ? theme.muted : theme.border;
		ctx.lineWidth = 1;
		ctx.strokeRect(r.x + GAP + 0.5, r.y + GAP + 0.5, r.w - 2 * GAP - 1, r.h - 2 * GAP - 1);

		ctx.save();
		ctx.beginPath();
		ctx.rect(r.x, r.y, r.w, HEADER);
		ctx.clip();
		let right = r.x + r.w - PAD - 2;
		if (node.problems > 0 && r.w > 120) {
			right -= draw_badge(count(node.problems), right, r.y + 4) + 6;
		}
		ctx.font = `600 12px ${theme.font}`;
		ctx.fillStyle = state.hover === item ? theme.link : theme.text;
		const name = fit_text(node.name + "/", right - r.x - 8);
		ctx.fillText(name, r.x + 6, r.y + 15);
		const used = ctx.measureText(name).width;
		ctx.font = `11px ${theme.font}`;
		ctx.fillStyle = theme.muted;
		const stats = fit_text(node.total ? `${percent(coverage_of(node))} of ${count(node.total)}` : "nothing declared", right - r.x - 16 - used);
		if (stats && !stats.startsWith("…")) {
			ctx.fillText(stats, r.x + 14 + used, r.y + 15);
		}
		ctx.restore();
	};

	const draw_leaf = (item, r) => {
		const node = item.node;
		const x = r.x + GAP, y = r.y + GAP, w = r.w - 2 * GAP, h = r.h - 2 * GAP;
		if (w <= 0 || h <= 0) {
			return;
		}
		ctx.fillStyle = fill_for(coverage_of(node));
		ctx.fillRect(x, y, w, h);
		if (item.group) {
			// more inside: a folded corner
			ctx.fillStyle = theme.frame;
			ctx.beginPath();
			ctx.moveTo(x + w - 9, y);
			ctx.lineTo(x + w, y + 9);
			ctx.lineTo(x + w, y);
			ctx.fill();
		}
		if (state.hover === item) {
			ctx.strokeStyle = theme.text;
			ctx.globalAlpha *= 0.55;
			ctx.lineWidth = 1.5;
			ctx.strokeRect(x + 0.75, y + 0.75, w - 1.5, h - 1.5);
			ctx.globalAlpha /= 0.55;
		}
		if (w < 22 || h < 15) {
			return;
		}

		ctx.save();
		ctx.beginPath();
		ctx.rect(x, y, w, h);
		ctx.clip();
		let right = x + w - 4;
		if (node.problems > 0 && w > 56 && h > 22) {
			right -= draw_badge(count(node.problems), right, y + 4) + 4;
		}
		ctx.font = `600 12px ${theme.font}`;
		ctx.fillStyle = theme.text;
		ctx.fillText(fit_text(node.name + (item.group ? "/" : ""), right - x - 6), x + 6, y + 16);
		if (h > 36 && w > 40) {
			ctx.font = `11px ${theme.font}`;
			ctx.globalAlpha *= 0.75;
			ctx.fillText(fit_text(node.total ? `${percent(coverage_of(node))} of ${count(node.total)}` : "nothing declared", w - 12), x + 6, y + 31);
			ctx.globalAlpha /= 0.75;
		}
		ctx.restore();
	};

	const is_selected = item => state.selected && item.leaf && !item.group && item.node.pkg === state.selected;

	function draw(now) {
		frame = 0;
		const dpr = window.devicePixelRatio || 1;
		ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
		ctx.fillStyle = theme.bg;
		ctx.fillRect(0, 0, width, height);

		const t = animation ? Math.min(1, (now - animation.start) / 380) : 1;
		const e = ease(t);
		shown = new Map();
		let selected = null;
		for (const item of layout) {
			const r = item.from && t < 1 ? lerp(item.from, item.r, e) : item.r;
			ctx.globalAlpha = !item.from && t < 1 ? e : 1;
			shown.set(item.node.path, r);
			item.shown = r;
			if (item.leaf) {
				draw_leaf(item, r);
			} else {
				draw_group(item, r);
			}
			if (is_selected(item)) {
				selected = r;
			}
		}
		ctx.globalAlpha = 1;
		if (selected) {
			ctx.strokeStyle = theme.link;
			ctx.lineWidth = 2.5;
			ctx.strokeRect(selected.x + 1.25, selected.y + 1.25, selected.w - 2.5, selected.h - 2.5);
		}
		if (t < 1) {
			request_draw();
		}
	}

	const resize = () => {
		const rect = map.getBoundingClientRect();
		const h = window.innerWidth < 720 ? 420 : Math.round(Math.max(380, Math.min(720, window.innerHeight * 0.66)));
		if (Math.round(rect.width) === width && h === height) {
			return;
		}
		width = Math.round(rect.width);
		height = h;
		const dpr = window.devicePixelRatio || 1;
		canvas.width = width * dpr;
		canvas.height = height * dpr;
		canvas.style.height = height + "px";
		panel.style.setProperty("--odin-report-map-height", height + "px");
		relayout(false);
		// resizing clears the canvas, so draw now rather than leave it blank for a frame
		cancelAnimationFrame(frame);
		draw(performance.now());
	};

	// Pointing and keys

	const item_at = (x, y) => {
		for (let i = layout.length - 1; i >= 0; i--) {
			const r = layout[i].shown || layout[i].r;
			if (x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h) {
				return layout[i];
			}
		}
		return null;
	};
	const point_of = ev => {
		const rect = canvas.getBoundingClientRect();
		return [ev.clientX - rect.left, ev.clientY - rect.top];
	};

	const counts_html = node => CATEGORIES.filter(c => node.counts[c.key] > 0)
		.map(c => `<span class="odin-report-badge ${c.badge}">${c.key === "overview" ? (node.pkg && node.children.length === 0 ? "No overview" : `${count(node.counts[c.key])} without an overview`) : `${c.label} ${count(node.counts[c.key])}`}</span>`).join(" ");
	const bar_html = node => {
		const c = coverage_of(node);
		return `<span class="odin-report-bar"><span style="width:${c === null ? 0 : c * 100}%;background:${fill_for(c)}"></span></span>`;
	};

	canvas.addEventListener("mousemove", ev => {
		const [x, y] = point_of(ev);
		const item = item_at(x, y);
		if (item !== state.hover) {
			state.hover = item;
			canvas.style.cursor = item ? "pointer" : "";
			request_draw();
		}
		if (!item) {
			tip.hidden = true;
			return;
		}
		const node = item.node;
		tip.innerHTML = `
			<b>${escape(title_of(node))}</b>
			${item.group ? `<span class="odin-report-tip-note">${plural(node.packages, "package")}</span>` : ""}
			<div>${bar_html(node)} ${node.total ? `${count(node.total - node.undoc)} of ${count(node.total)} documented` : "Nothing declared"}</div>
			${node.problems ? `<div>${counts_html(node)}</div>` : ""}`;
		tip.hidden = false;
		const box = map.getBoundingClientRect();
		const tw = tip.offsetWidth, th = tip.offsetHeight;
		let tx = x + 14, ty = y + 14;
		if (tx + tw > box.width - 4) {
			tx = x - tw - 14;
		}
		if (ty + th > box.height - 4) {
			ty = y - th - 14;
		}
		tip.style.left = Math.max(4, tx) + "px";
		tip.style.top  = Math.max(4, ty) + "px";
	});
	canvas.addEventListener("mouseleave", () => {
		state.hover = null;
		tip.hidden = true;
		canvas.style.cursor = "";
		request_draw();
	});
	canvas.addEventListener("click", ev => {
		const item = item_at(...point_of(ev));
		if (item) {
			open_item(item);
		}
	});
	const open_item = (item, replace = false) => {
		const node = item.node;
		if (item.group) {
			go(`#${node.path}`, replace);
		} else if (node.pkg) {
			go(`#${node.pkg.import}`, replace);
		}
	};

	// arrow keys move to the nearest package that way
	canvas.addEventListener("keydown", ev => {
		const moves = {ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1]};
		if (ev.key === "Escape") {
			if (state.zoom !== root) {
				ev.preventDefault();
				go(state.zoom.parent === root ? "#" : `#${state.zoom.parent.path}`);
			}
			return;
		}
		if (ev.key === "Enter") {
			const current = layout.find(is_selected);
			if (state.selected) {
				window.open(state.selected.url, "_blank", "noopener");
				ev.preventDefault();
			} else if (current) {
				open_item(current);
			}
			return;
		}
		const move = moves[ev.key];
		if (!move) {
			return;
		}
		ev.preventDefault();
		const leaves = layout.filter(item => item.leaf && (item.r.w > 2 && item.r.h > 2));
		const current = layout.find(is_selected);
		if (!current) {
			if (leaves.length) {
				open_item(leaves[0], true);
			}
			return;
		}
		// only boxes wholly past the edge, preferring those alongside, then the nearest
		const a = current.r;
		const span = (r, axis) => axis ? [r.y, r.y + r.h] : [r.x, r.x + r.w];
		const vertical = move[1] !== 0;
		let best = null, best_score = Infinity;
		for (const item of leaves) {
			if (item === current) {
				continue;
			}
			const b = item.r;
			const gap = move[0] > 0 ? b.x - (a.x + a.w) : move[0] < 0 ? a.x - (b.x + b.w) : move[1] > 0 ? b.y - (a.y + a.h) : a.y - (b.y + b.h);
			if (gap < -1) {
				continue;
			}
			const [a0, a1] = span(a, !vertical), [b0, b1] = span(b, !vertical);
			const apart = Math.max(0, b0 - a1, a0 - b1);
			const offset = Math.abs((b0 + b1) / 2 - (a0 + a1) / 2);
			const score = gap + 4 * apart + 0.1 * offset;
			if (score < best_score) {
				best = item;
				best_score = score;
			}
		}
		if (best) {
			if (best.group) {
				// over a folded directory, select into it rather than past it
				const first = items_of(best.node)[0];
				if (first && first.node.pkg && first.node.children.length === 0) {
					go(`#${first.node.pkg.import}`, true);
					return;
				}
			}
			open_item(best, true);
		}
	});

	// Where we are: the address says, so every view can be linked to and Back works

	const go = (hash, replace = false) => {
		if (hash === "#") {
			hash = location.pathname;
		}
		if (replace) {
			history.replaceState(null, "", hash);
		} else {
			history.pushState(null, "", hash);
		}
		apply_address();
	};

	const apply_address = () => {
		const hash = decodeURIComponent(location.hash.slice(1));
		const zoom_before = state.zoom;
		state.view = "group";
		state.category = null;
		state.selected = null;
		if (hash.startsWith("=")) {
			state.view = "category";
			state.category = CATEGORIES.find(c => c.key === hash.slice(1)) || CATEGORIES[0];
		} else if (hash.includes(":")) {
			const p = pkg_by_import.get(hash);
			if (p) {
				state.view = "package";
				state.selected = p;
				// zoomed in far enough for its own box to show, big enough to read
				const own_box = layout.some(item => item.leaf && !item.group && item.node.pkg === p && item.r.w >= 72 && item.r.h >= 40);
				if (!is_inside(p.node, state.zoom) || !own_box) {
					state.zoom = p.node.children.length ? p.node : (p.node.parent || root);
				}
			}
		} else {
			const node = nodes.get(hash);
			state.zoom = node && node.children.length ? node : root;
			if (node && !node.children.length && node.pkg) {
				state.zoom = node.parent || root;
				state.view = "package";
				state.selected = node.pkg;
			}
		}
		render_crumbs();
		render_panel();
		relayout(state.zoom !== zoom_before);
		if (state.selected) {
			find.value = "";
		}
	};
	window.addEventListener("popstate", apply_address);
	report.addEventListener("click", ev => {
		const a = ev.target.closest && ev.target.closest("a[href^='#']");
		if (a && ev.button === 0 && !ev.ctrlKey && !ev.metaKey && !ev.shiftKey) {
			ev.preventDefault();
			go(a.getAttribute("href"));
		}
	});

	find.addEventListener("change", () => {
		const p = pkg_by_import.get(find.value.trim());
		if (p) {
			go(`#${p.import}`);
			canvas.focus({preventScroll: true});
		}
	});
	find.addEventListener("keydown", ev => {
		if (ev.key !== "Enter") {
			return;
		}
		const query = find.value.trim().toLowerCase();
		const p = pkg_by_import.get(find.value.trim()) || data.packages.find(p => p.import.toLowerCase().includes(query));
		if (p && query) {
			go(`#${p.import}`);
		}
	});

	report.querySelectorAll(".odin-report-size button").forEach(button => {
		button.addEventListener("click", () => {
			state.size = button.dataset.size;
			try {
				localStorage.setItem("odin-report-size", state.size);
			} catch {
			}
			update_size_buttons();
			relayout(true);
		});
	});
	const update_size_buttons = () => {
		report.querySelectorAll(".odin-report-size button").forEach(b => b.setAttribute("aria-pressed", String(b.dataset.size === state.size)));
	};

	// The panel beside the map

	const render_crumbs = () => {
		const trail = [];
		for (let n = state.zoom; n; n = n.parent) {
			trail.unshift(n);
		}
		crumbs.innerHTML = trail.map((n, i) => i === trail.length - 1
			? `<span aria-current="location">${escape(n === root ? "All" : n.name)}</span>`
			: `<a href="${n === root ? "#" : `#${escape(n.path)}`}">${escape(n === root ? "All" : n.name)}</a>`
		).join(`<span class="odin-report-crumb-sep">/</span>`);
	};

	const source_of = (p, file, line) => file ? `${p.source}/${file}#L${line}` : p.source;
	const issue_html = (p, [kind, name, detail, file, line], with_pkg = false) => {
		const what = {
			link:    `${with_code("`" + detail + "`")} doesn't resolve`,
			stale:   with_code(detail),
			param:   with_code(detail),
			missing: with_code(detail),
			example: `Example doesn't parse: ${with_code(detail)}`,
			output:  "An Output with no Example",
		}[kind] || with_code(detail);
		const target = name ? `<a href="${escape(p.url)}#${escape(name)}">${with_pkg ? `${escape(p.import)}.` : ""}${escape(name)}</a>` : `<a href="${escape(p.url)}">${with_pkg ? `${escape(p.import)} ` : ""}overview</a>`;
		return `<li>${target}<span class="odin-report-what">${what}</span>${file || !name ? `<a class="odin-report-src" href="${escape(source_of(p, file, line))}">${file ? `${escape(file)}:${line}` : "source"}</a>` : ""}</li>`;
	};

	const NAMES_SHOWN = 300;
	const names_html = (p, kind, names) => {
		const shown = names.slice(0, NAMES_SHOWN);
		const links = list => list.map(n => `<a href="${escape(p.url)}#${escape(n)}">${escape(n)}</a>`).join(" ");
		return `<details ${names.length <= 60 ? "open" : ""}><summary>${DECL_KINDS[kind]} <span class="odin-report-count">${count(names.length)}</span></summary>
			<div class="odin-report-names" data-kind="${kind}">${links(shown)}${names.length > NAMES_SHOWN ? ` <button type="button" class="odin-report-more">Show all ${count(names.length)}</button>` : ""}</div></details>`;
	};

	const render_package = p => {
		const by_category = CATEGORIES.map(c => ({c, issues: p.issues.filter(i => c.kinds.includes(i[0]))}));
		const undocumented = Object.entries(p.undocumented).filter(([, names]) => names.length);
		panel.innerHTML = `
			<h2>${escape(p.import)}</h2>
			<p class="odin-report-links"><a href="${escape(p.url)}">Docs</a> · <a href="${escape(p.source)}">Source</a></p>
			<p>${bar_html(p)} ${p.total ? `${count(p.total - p.undoc)} of ${count(p.total)} declarations documented (${percent(coverage_of(p))})` : "Nothing declared"}</p>
			${p.overview ? "" : `<p class="odin-report-flag"><span class="odin-report-badge kind-pkg">No overview</span> The package has no doc comment of its own.</p>`}
			${by_category.filter(({issues}) => issues.length).map(({c, issues}) => `
				<h3><span class="odin-report-badge ${c.badge}">${c.label}</span> <span class="odin-report-count">${count(issues.length)}</span></h3>
				<ul class="odin-report-issues">${issues.map(i => issue_html(p, i)).join("")}</ul>`).join("")}
			${p.problems === 0 ? `<p class="odin-report-good">No problems found.</p>` : ""}
			${undocumented.length ? `<h3>Undocumented <span class="odin-report-count">${count(p.undoc)}</span></h3>${undocumented.map(([kind, names]) => names_html(p, kind, names)).join("")}` : ""}
		`;
		panel.querySelectorAll(".odin-report-more").forEach(button => {
			button.addEventListener("click", () => {
				const div = button.parentElement;
				const names = p.undocumented[div.dataset.kind];
				div.innerHTML = names.map(n => `<a href="${escape(p.url)}#${escape(n)}">${escape(n)}</a>`).join(" ");
			});
		});
	};

	const packages_under = node => {
		const out = [];
		const walk = n => {
			if (n.pkg) {
				out.push(n.pkg);
			}
			n.children.forEach(walk);
		};
		walk(node);
		return out;
	};

	const render_group = node => {
		const pkgs = packages_under(node).sort((a, b) => b.problems - a.problems || b.undoc - a.undoc || a.import.localeCompare(b.import));
		panel.innerHTML = `
			<h2>${escape(title_of(node))}</h2>
			<p>${bar_html(node)} ${count(node.total - node.undoc)} of ${count(node.total)} declarations documented (${percent(coverage_of(node))}) in ${plural(node.packages, "package")}</p>
			${node.problems ? `<p>${counts_html(node)}</p>` : `<p class="odin-report-good">No problems found.</p>`}
			<table class="odin-report-table">
				<thead><tr><th>Package</th><th>Documented</th><th>Problems</th></tr></thead>
				<tbody>${pkgs.map(p => `<tr>
					<td><a href="#${escape(p.import)}">${escape(p.import)}</a></td>
					<td>${bar_html(p)} ${p.total ? percent(coverage_of(p)) : "–"}</td>
					<td>${p.problems ? count(p.problems) : ""}</td>
				</tr>`).join("")}</tbody>
			</table>`;
	};

	const render_category = c => {
		const pkgs = data.packages.filter(p => p.counts[c.key] > 0);
		let body;
		if (c.key === "overview") {
			body = `<ul class="odin-report-issues">${pkgs.map(p => `<li><a href="#${escape(p.import)}">${escape(p.import)}</a><span class="odin-report-what">${p.total ? plural(p.total, "declaration") : "nothing declared"}</span><a class="odin-report-src" href="${escape(p.source)}">source</a></li>`).join("")}</ul>`;
		} else {
			body = `<ul class="odin-report-issues">${pkgs.flatMap(p => p.issues.filter(i => c.kinds.includes(i[0])).map(i => issue_html(p, i, true))).join("")}</ul>`;
		}
		panel.innerHTML = `
			<h2><span class="odin-report-badge ${c.badge}">${c.label}</span> <span class="odin-report-count">${count(root.counts[c.key])}</span></h2>
			<p class="odin-report-links">${CATEGORIES.filter(other => other !== c).map(other => `<a href="#=${other.key}">${other.label}</a>`).join(" · ")} · <a href="#">All packages</a></p>
			${pkgs.length ? body : `<p class="odin-report-good">${c.none}</p>`}`;
	};

	const render_panel = () => {
		if (state.view === "package") {
			render_package(state.selected);
		} else if (state.view === "category") {
			render_category(state.category);
		} else {
			render_group(state.zoom);
		}
		panel.scrollTop = 0;
	};

	// The theme can change under us
	const observer = new MutationObserver(() => {
		read_theme();
		render_panel();
		request_draw();
	});
	observer.observe(document.body, {attributes: true, attributeFilter: ["class"]});
	observer.observe(document.documentElement, {attributes: true, attributeFilter: ["class"]});

	read_theme();
	update_size_buttons();
	new ResizeObserver(resize).observe(map);
	window.addEventListener("resize", resize);
	resize();
	apply_address();
})();
