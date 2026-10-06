"use strict";

const userAgent = navigator.userAgent;
const osList = [
	{lookFor: "Win",     name: "windows"},
	{lookFor: "Mac",     name: "macos"},
	{lookFor: "X11",     name: "unix"},
	{lookFor: "Linux",   name: "linux"},
	{lookFor: "iPhone",  name: "ios"},
	{lookFor: "Android", name: "android"},
];
for (const os of osList) {
	if (userAgent.includes(os.lookFor)) {
		document.body.classList.add(`os-${os.name}`);	
	}	
}

document.addEventListener("DOMContentLoaded", () => {
	const scope = document.querySelector(".documentation") || document;
	scope.querySelectorAll("pre").forEach((pre) => {
		if (pre.querySelector(".copy-code")) {
			return;
		}
		const btn = document.createElement("button");
		btn.type        = "button";
		btn.className   = "copy-code";
		btn.textContent = "Copy";
		btn.setAttribute("aria-label", "Copy code to clipboard");
		btn.addEventListener("click", async () => {
			const code = pre.querySelector("code") || pre;
			btn.hidden = true;
			const text = code.innerText.replace(/\s+$/, "");
			btn.hidden = false;
			try {
				await navigator.clipboard.writeText(text);
			} catch {
				const r = document.createRange();
				r.selectNodeContents(code);
				const sel = getSelection();
				sel.removeAllRanges();
				sel.addRange(r);
				try {
					document.execCommand("copy");
				} catch {
				}
				sel.removeAllRanges();
			}
			btn.textContent = "Copied";
			setTimeout(() => (btn.textContent = "Copy"), 1200);
		});
		pre.appendChild(btn);
	});
});

function text_at_point(x, y) {
	let node = null, offset = 0;
	if (document.caretPositionFromPoint) {
		const pos = document.caretPositionFromPoint(x, y);
		if (pos) {
			[node, offset] = [pos.offsetNode, pos.offset];
		}
	} else if (document.caretRangeFromPoint) {
		const range = document.caretRangeFromPoint(x, y);
		if (range) {
			[node, offset] = [range.startContainer, range.startOffset];
		}
	}
	return node && node.nodeType === Node.TEXT_NODE ? [node, offset] : null;
}

async function copy_text(text) {
	try {
		await navigator.clipboard.writeText(text);
	} catch {
		const area = document.createElement("textarea");
		area.value = text;
		area.style.position = "fixed";
		area.style.opacity = "0";
		document.body.appendChild(area);
		area.select();
		try {
			document.execCommand("copy");
		} catch {
		}
		area.remove();
	}
}

function flash_copied(btn) {
	const label = btn.dataset.label || btn.textContent;
	btn.dataset.label = label;
	btn.textContent = "copied";
	btn.classList.add("copied");
	clearTimeout(btn.copied_timer);
	btn.copied_timer = setTimeout(() => {
		btn.textContent = label;
		btn.classList.remove("copied");
	}, 1200);
}

// where j and k bring a declaration to: below the navbar and the section label
const READING_LINE = 100;

// the declaration across that line, else the first in view below it
// a declaration with a block of its own, or a row in a package listing its procedures one per row
const DECLARATIONS = ".documentation .pkg-entity, .documentation .doc-dense tr[id]";

function declaration_being_read() {
	for (const entity of document.querySelectorAll(DECLARATIONS)) {
		if (entity.offsetParent === null) {
			continue;
		}
		const r = entity.getBoundingClientRect();
		// rows touch, so the one above ends a fraction past the line
		if (r.bottom > READING_LINE + 2) {
			return r.top < window.innerHeight ? entity : null;
		}
	}
	return null;
}

function is_typing(ev) {
	return ev.target.closest && ev.target.closest("input, textarea, select, [contenteditable]");
}

document.addEventListener("click", async (ev) => {
	const btn = ev.target.closest(".copy-import");
	if (!btn) {
		return;
	}
	await copy_text(btn.dataset.copy);
	flash_copied(btn);
});

{
	const btn = document.createElement("button");
	btn.type        = "button";
	btn.className   = "copy-link";
	btn.textContent = "copy link";
	btn.title       = "Copy a link to this declaration";

	const report = document.createElement("a");
	report.className = "doc-report";
	report.target    = "_blank";
	report.rel       = "noopener";
	report.title     = "Report a problem with these docs";
	report.setAttribute("aria-label", report.title);
	report.innerHTML = `<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M8 1.75 15 14.25H1z" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/><path d="M8 6.25v3.75M8 12.1v.01" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>`;

	const issue_url = (h3, source) => {
		const repo = source.href.match(/^https:\/\/github\.com\/[^/]+\/[^/]+/);
		if (!repo) {
			return null;
		}
		const import_path = document.querySelector(".odin-import .string");
		const pkg = import_path ? import_path.textContent.replace(/"/g, "") : document.title.replace(/^package\s+|\s+-.*$/g, "");
		const title = `Docs: ${pkg}.${h3.id}`;
		const body = `${location.origin}${location.pathname}#${h3.id}\n${source.href}\n\n`;
		return `${repo[0]}/issues/new?title=${encodeURIComponent(title)}&body=${encodeURIComponent(body)}`;
	};

	const place = (h3) => {
		if (h3 && btn.parentElement !== h3.firstElementChild) {
			h3.firstElementChild.appendChild(btn);
			const links = h3.querySelectorAll(".doc-source > a");
			const source = links[links.length - 1];
			const url = source && issue_url(h3, source);
			if (url) {
				report.href = url;
				source.parentElement.appendChild(report);
			} else {
				report.remove();
			}
		}
	};
	document.addEventListener("mouseover", ev => place(ev.target.closest && ev.target.closest(".pkg-entity > h3")));
	document.addEventListener("focusin", ev => {
		if (ev.target !== btn && ev.target !== report) {
			place(ev.target.closest(".pkg-entity > h3"));
		}
	});
	btn.addEventListener("click", async () => {
		await copy_text(location.origin + location.pathname + "#" + btn.closest("h3").id);
		flash_copied(btn);
	});

	// l copies a link to the declaration being read
	window.addEventListener("keydown", async ev => {
		if (ev.key !== "l" || ev.ctrlKey || ev.metaKey || ev.altKey || is_typing(ev)) {
			return;
		}
		const entity = declaration_being_read();
		if (entity && entity.matches("tr")) {
			ev.preventDefault();
			await copy_text(location.origin + location.pathname + "#" + entity.id);
			entity.classList.add("doc-dense-copied");
			setTimeout(() => entity.classList.remove("doc-dense-copied"), 1200);
			return;
		}
		const h3 = entity && entity.querySelector(":scope > h3");
		if (!h3) {
			return;
		}
		ev.preventDefault();
		place(h3);
		await copy_text(location.origin + location.pathname + "#" + h3.id);
		flash_copied(btn);
	});
}

// A dense row's Source link shows when it's hovered, built from the table's source directory and the row's file and line
{
	const link = document.createElement("a");
	link.className = "doc-dense-source";
	link.textContent = "Source";
	// and, where there is one, its page in the upstream documentation, e.g. Microsoft Learn's
	const upstream = document.createElement("a");
	upstream.className = "doc-upstream doc-dense-upstream";
	document.addEventListener("mouseover", ev => {
		const row = ev.target.closest && ev.target.closest(".doc-dense tr[data-src]");
		if (row && link.parentElement !== row.lastElementChild) {
			const table = row.closest(".doc-dense");
			link.href = table.dataset.source + row.dataset.src;
			row.lastElementChild.prepend(link);
			if (table.dataset.upstream && row.dataset.up !== "") {
				upstream.href = table.dataset.upstream.replace("{name}", encodeURIComponent(row.dataset.up || row.id));
				upstream.textContent = table.dataset.upstreamTitle;
				link.after(upstream);
			} else {
				upstream.remove();
			}
		}
	});
}

// A declaration's examples from odin-lang/examples: excerpts of the first few, and links to the rest,
// from the package's examples.json, fetched when the first of them is opened
{
	let loading = null;
	const escape = text => String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
	document.addEventListener("toggle", async ev => {
		const details = ev.target;
		if (!details.open || !details.classList || !details.classList.contains("doc-examples") || details.dataset.loaded) {
			return;
		}
		details.dataset.loaded = "1";
		const body = details.querySelector(".doc-examples-body");
		body.textContent = "Loading…";
		loading = loading || fetch("examples.json").then(r => r.ok ? r.json() : null).catch(() => null);
		const examples = await loading;
		const uses = examples && examples.decls[details.dataset.name];
		if (!uses) {
			body.textContent = "The examples couldn't be loaded.";
			delete details.dataset.loaded;
			return;
		}
		// each example's page, and the line using it there
		const at = path => `${examples.repo}/blob/${examples.commit}/${path}`;
		const shown = uses.filter(u => u.html);
		const rest = uses.filter(u => !u.html);
		body.innerHTML = shown.map(u => `
			<div class="doc-example">
				<div class="doc-example-head">
					<a href="${escape(u.u)}">${escape(u.p)}</a>
					<span class="doc-example-at">· <a href="${escape(u.at)}">${escape(u.f)}:${u.l}</a></span>
					${u.license ? `<span class="doc-example-license">· <a href="${escape(at(u.license_path))}" title="${escape(u.license)}">its own licence</a></span>` : ""}
				</div>
				<pre class="doc-example-code"><code class="hljs nohighlight">${u.html}</code></pre>
			</div>`).join("") +
			(rest.length ? `<p class="doc-example-more">${shown.length ? "Also in" : "In"} ${rest.map(u => `<a href="${escape(u.at)}">${escape(u.p)}</a>`).join(", ")}</p>` : "");
	}, true);
}

// Long Related lists arrive as names, and become links when first opened
document.addEventListener("toggle", ev => {
	const details = ev.target;
	if (!details.open || !details.classList || !details.classList.contains("doc-related-lazy")) {
		return;
	}
	const ul = details.querySelector(":scope > ul");
	if (ul && ul.childElementCount === 0) {
		ul.innerHTML = details.dataset.names.split(" ").map(token => {
			const [name, kind] = token.split(":");
			return `<li><a href="#${name}">${name}</a>${kind === "g" ? "&nbsp;<em>(procedure groups)</em>" : ""}</li>`;
		}).join("");
	}
}, true);

document.addEventListener("click", ev => {
	const btn = ev.target.closest(".doc-code-expand");
	if (!btn) {
		return;
	}
	const label = btn.dataset.label || btn.textContent;
	btn.dataset.label = label;
	const expanded = btn.previousElementSibling.classList.toggle("expanded");
	btn.setAttribute("aria-expanded", expanded);
	btn.textContent = expanded ? "Show fewer lines" : label;
});

document.addEventListener("DOMContentLoaded", () => {
	const list = document.querySelector("#pkg-sidebar .odin-sidebar-content");
	const active = list && list.querySelector("a.active");
	if (!active || list.scrollHeight <= list.clientHeight) {
		return;
	}
	const top = active.getBoundingClientRect().top - list.getBoundingClientRect().top;
	if (top < 0 || top > list.clientHeight - active.offsetHeight) {
		list.scrollTop += top - list.clientHeight/2;
	}
});

document.addEventListener("DOMContentLoaded", () => {
	const section = document.querySelector("section.documentation");
	const headers = section ? [...section.querySelectorAll(":scope > h2.pkg-header")] : [];
	if (headers.length === 0) {
		return;
	}
	const label = document.createElement("div");
	label.className = "odin-section-label";
	label.setAttribute("aria-hidden", "true");
	label.appendChild(document.createElement("span"));
	section.prepend(label);

	let scheduled = false;
	const update = () => {
		scheduled = false;
		const top = label.getBoundingClientRect().top + label.firstElementChild.offsetHeight;
		let current = null;
		for (const h of headers) {
			if (h.offsetParent !== null && h.getBoundingClientRect().bottom < top) {
				current = h;
			}
		}
		label.classList.toggle("visible", current !== null);
		if (current !== null) {
			label.firstElementChild.textContent = current.textContent;
		}
	};
	window.addEventListener("scroll", () => {
		if (!scheduled) {
			scheduled = true;
			requestAnimationFrame(update);
		}
	}, {passive: true});
	update();
});

// A class in the Contents panel shows its methods when toggled, and while you are reading it
document.addEventListener("DOMContentLoaded", () => {
	const toc = document.getElementById("TableOfContents");
	if (!toc || !toc.querySelector("li.toc-class")) {
		return;
	}
	const set_open = (li, open) => {
		li.classList.toggle("open", open);
		li.firstElementChild.setAttribute("aria-expanded", open);
	};

	let opened_by_reading = null;
	toc.addEventListener("click", ev => {
		const button = ev.target.closest(".toc-class-toggle");
		if (button) {
			const li = button.parentElement;
			set_open(li, !li.classList.contains("open"));
			if (li === opened_by_reading) {
				opened_by_reading = null; // it stays as the reader leaves it
			}
		}
	});

	// odin-lang.org's script.js marks the entry of what you are reading as active
	new MutationObserver(() => {
		const active = toc.querySelector("li.active");
		const li = active && active.closest("li.toc-class");
		if (opened_by_reading && opened_by_reading !== li) {
			set_open(opened_by_reading, false);
			opened_by_reading = null;
		}
		if (li && !li.classList.contains("open")) {
			set_open(li, true);
			opened_by_reading = li;
			active.querySelector(":scope > a").scrollIntoView({block: "nearest"});
		}
	}).observe(toc, {attributes: true, attributeFilter: ["class"], subtree: true});
});

// j and k move to the next and previous declaration
window.addEventListener("keydown", ev => {
	if (ev.ctrlKey || ev.metaKey || ev.altKey || (ev.key !== "j" && ev.key !== "k")) {
		return;
	}
	if (ev.target.closest && ev.target.closest("input, textarea, select, [contenteditable]")) {
		return;
	}
	const entities = [...document.querySelectorAll(DECLARATIONS)]
		.filter(e => e.offsetParent !== null)
		.map(e => e.getBoundingClientRect().top)
		.sort((a, b) => a - b);
	if (entities.length === 0) {
		return;
	}
	ev.preventDefault();
	const line = READING_LINE;
	const target = ev.key === "j" ? entities.find(top => top > line + 2) : entities.findLast(top => top < line - 2);
	if (target !== undefined) {
		window.scrollBy(0, target - line);
	}
});

window.addEventListener("keydown", ev => {
	if (ev.ctrlKey || ev.metaKey || ev.altKey || (ev.key !== "s" && ev.key !== "d") || is_typing(ev)) {
		return;
	}
	if (ev.key === "s") {
		const entity = declaration_being_read();
		if (entity && entity.matches("tr") && entity.dataset.src) {
			ev.preventDefault();
			location.href = entity.closest(".doc-dense").dataset.source + entity.dataset.src;
			return;
		}
		const links = entity ? [...entity.querySelectorAll(":scope > h3 .doc-source > a")] : [];
		const source = links.find(a => a.textContent.startsWith("Source"));
		if (source) {
			ev.preventDefault();
			source.click();
		}
		return;
	}
	const descriptions = [...document.querySelectorAll(".documentation .pkg-entity details.odin-doc-toggle")]
		.filter(d => d.querySelector(":scope > summary > span"));
	if (descriptions.length === 0) {
		return;
	}
	ev.preventDefault();
	// the declaration being read stays where it is, however much everything above it changes height
	const anchor = declaration_being_read();
	const before = anchor && anchor.getBoundingClientRect().top;
	const open = !descriptions.some(d => d.open);
	for (const d of descriptions) {
		d.open = open;
	}
	if (anchor) {
		window.scrollBy(0, anchor.getBoundingClientRect().top - before);
	}
});

// Hovering a parameter in a signature highlights its description in the Inputs list, and the other way around
{
	const can_highlight = typeof CSS !== "undefined" && CSS.highlights && typeof Highlight !== "undefined";
	let active = null;

	const clear = () => {
		if (active) {
			active.classList.remove("doc-param-active");
			active = null;
		}
		if (can_highlight) {
			CSS.highlights.delete("odin-param");
		}
	};
	const names_of = li => li.querySelector(".doc-param-name").textContent.split(",").map(name => name.trim());
	const signature_of = entity => entity.querySelector(":scope > div > pre.doc-code");
	const entity_of = el => el.closest(".pkg-entity");
	const rows_of = entity => entity.querySelectorAll("ul.doc-params > li");

	// where a signature declares `name`: followed by `:` or `,`, as in `(a, b: int, c := 0)`
	const ranges_of = (pre, names) => {
		const walker = document.createTreeWalker(pre, NodeFilter.SHOW_TEXT);
		const nodes = [];
		let text = "";
		for (let node; (node = walker.nextNode()); ) {
			if (!node.parentElement.closest(".copy-code")) {
				nodes.push([node, text.length]);
				text += node.data;
			}
		}
		const at = offset => {
			let i = nodes.length - 1;
			while (i > 0 && nodes[i][1] > offset) {
				i -= 1;
			}
			return [nodes[i][0], offset - nodes[i][1]];
		};
		const ranges = [];
		for (const name of names) {
			const re = new RegExp(`(^|[^\\w.])(${name.replace(/[^\w]/g, "")})(?=\\s*[:,])`, "g");
			for (let m; (m = re.exec(text)); ) {
				const start = m.index + m[1].length;
				const range = new Range();
				range.setStart(...at(start));
				range.setEnd(...at(start + m[2].length));
				ranges.push(range);
			}
		}
		return ranges;
	};
	const light = (li, ranges) => {
		if (active !== li) {
			clear();
			active = li;
			li.classList.add("doc-param-active");
		}
		if (can_highlight && ranges.length > 0) {
			CSS.highlights.set("odin-param", new Highlight(...ranges));
		}
	};

	// the word under the mouse in a signature
	const word_at = (x, y) => {
		const at = text_at_point(x, y);
		if (!at) {
			return null;
		}
		const [node, offset] = at;
		const text = node.data;
		let start = offset, end = offset;
		while (start > 0 && /\w/.test(text[start - 1])) {
			start -= 1;
		}
		while (end < text.length && /\w/.test(text[end])) {
			end += 1;
		}
		if (start === end || text[start - 1] === "." || !/^\s*[:,]/.test(text.slice(end))) {
			return null;
		}
		const range = new Range();
		range.setStart(node, start);
		range.setEnd(node, end);
		return [text.slice(start, end), range];
	};

	document.addEventListener("mouseover", ev => {
		const li = ev.target.closest && ev.target.closest("ul.doc-params > li");
		if (!li) {
			return;
		}
		const pre = signature_of(entity_of(li));
		light(li, pre ? ranges_of(pre, names_of(li)) : []);
	});
	document.addEventListener("mouseout", ev => {
		const li = ev.target.closest && ev.target.closest("ul.doc-params > li");
		if (li && li === active && !li.contains(ev.relatedTarget)) {
			clear();
		}
	});

	let scheduled = false;
	document.addEventListener("mousemove", ev => {
		const pre = ev.target.closest && ev.target.closest(".pkg-entity > div > pre.doc-code:first-child");
		if (!pre || scheduled) {
			if (!pre && active && !active.matches(":hover")) {
				clear();
			}
			return;
		}
		scheduled = true;
		requestAnimationFrame(() => {
			scheduled = false;
			const found = word_at(ev.clientX, ev.clientY);
			const li = found && [...rows_of(entity_of(pre))].find(row => names_of(row).includes(found[0]));
			if (li) {
				light(li, [found[1]]);
			} else if (active) {
				clear();
			}
		});
	});
}

// ? lists the keyboard shortcuts
{
	let sheet = null;
	let opener = null;

	const close = () => {
		sheet.hidden = true;
		if (opener) {
			opener.focus();
		}
	};
	const open = () => {
		if (!sheet) {
			const mac = document.body.classList.contains("os-macos");
			const rows = [
				[[mac ? "\u2318K" : "Ctrl+K", "/"], "Search"],
				[["\u2191", "\u2193", "Enter"], "Choose a search result"],
				[[mac ? "\u2318Enter" : "Ctrl+Enter"], "Open a search result in a new tab"],
				[["Esc"], "Clear the search, then leave it"],
			];
			if (document.querySelector(".documentation .pkg-entity")) {
				rows.push([["j", "k"], "Next or previous declaration"]);
				rows.push([["s"], "Open the source of the declaration at the top"]);
				rows.push([["l"], "Copy a link to the declaration at the top"]);
				if (document.querySelector(".documentation .pkg-entity details.odin-doc-toggle > summary > span")) {
					rows.push([["d"], "Collapse or expand every description"]);
				}
				rows.push([[":Type"], "Search for what mentions a type"]);
			}
			if (document.querySelector(".odin-sidebar-toggle")) {
				rows.push([["[", "]"], "Collapse or expand the sidebars"]);
			}
			rows.push([["?"], "Show these shortcuts"]);

			sheet = document.createElement("div");
			sheet.className = "odin-shortcuts";
			sheet.hidden = true;
			sheet.innerHTML = `<div class="odin-shortcuts-box" role="dialog" aria-modal="true" aria-labelledby="odin-shortcuts-title" tabindex="-1">
				<h2 id="odin-shortcuts-title">Keyboard shortcuts</h2>
				<dl>${rows.map(([keys, what]) => `<dt>${keys.map(k => `<kbd>${k}</kbd>`).join(" ")}</dt><dd>${what}</dd>`).join("")}</dl>
			</div>`;
			sheet.addEventListener("click", ev => {
				if (ev.target === sheet) {
					close();
				}
			});
			document.body.appendChild(sheet);
		}
		opener = document.activeElement;
		sheet.hidden = false;
		sheet.firstElementChild.focus();
	};

	window.addEventListener("keydown", ev => {
		if (sheet && !sheet.hidden && (ev.key === "Escape" || ev.key === "?")) {
			ev.preventDefault();
			ev.stopPropagation();
			close();
			return;
		}
		if (ev.key !== "?" || ev.ctrlKey || ev.metaKey || ev.altKey) {
			return;
		}
		if (ev.target.closest && ev.target.closest("input, textarea, select, [contenteditable]")) {
			return;
		}
		ev.preventDefault();
		open();
	}, true);

	document.addEventListener("click", ev => {
		if (ev.target.closest && ev.target.closest(".odin-shortcuts-button")) {
			ev.preventDefault();
			open();
		}
	});
}

// [ and ] collapse or expand the packages and contents sidebars
window.addEventListener("keydown", ev => {
	if (ev.ctrlKey || ev.metaKey || ev.altKey || (ev.key !== "[" && ev.key !== "]")) {
		return;
	}
	if (ev.target.closest && ev.target.closest("input, textarea, select, [contenteditable]")) {
		return;
	}
	const button = document.querySelector(`.odin-sidebar-toggle[data-sidebar="${ev.key === "[" ? "pkg-sidebar" : "toc-sidebar"}"]`);
	if (button && button.offsetParent !== null) {
		ev.preventDefault();
		toggleSidebar(button);
	}
});

{
	const types_of = new Map();
	let popover = null;
	let current = null;
	let timer   = 0;

	const dense_definition = row => {
		const table = row.closest(".doc-dense");
		if (row.classList.contains("doc-dense-group")) {
			const members = [...row.parentElement.querySelectorAll(":scope > tr:not(.doc-dense-group) > td:first-child > a")].map(a => a.textContent);
			const shown = members.slice(0, 24).map(name => `\t${name},`);
			if (members.length > shown.length) {
				shown.push(`\t<span class="comment">// and ${members.length - shown.length} more</span>`);
			}
			return `${row.id} :: <span class="keyword-type">proc</span>{\n${shown.join("\n")}\n}`;
		}
		const code = row.querySelector("td > code");
		if (!code) {
			return null;
		}
		let head = `<span class="keyword-type">proc</span>`;
		if (table.dataset.cc) {
			head += ` <span class="string">"${table.dataset.cc}"</span>`;
		}
		const sig = code.innerHTML;
		return `${row.id} :: ${sig.startsWith('<span class="keyword-type">proc') ? sig : `${head} ${sig}`}`;
	};

	const definition_of = async (href) => {
		const url = new URL(href, location.href);
		const id = decodeURIComponent(url.hash.slice(1));
		const dir = url.pathname.replace(/\/?$/, "/");
		if (dir === location.pathname.replace(/\/?$/, "/")) {
			const h3 = document.getElementById(id);
			if (h3 && h3.matches(".doc-dense tr")) {
				return dense_definition(h3);
			}
			const preview = h3 && h3.parentElement.querySelector(":scope > div > template.doc-type-preview");
			if (preview) {
				return preview.innerHTML;
			}
			const pre = h3 && h3.parentElement.querySelector(":scope > div > pre.doc-code");
			if (!pre) {
				return null;
			}
			const definition = pre.cloneNode(true);
			definition.querySelectorAll(".copy-code").forEach(btn => btn.remove());
			return definition.innerHTML;
		}
		const json = dir + "types.json";
		if (!types_of.has(json)) {
			types_of.set(json, fetch(json).then(r => r.ok ? r.json() : null).catch(() => null));
		}
		const types = await types_of.get(json);
		return (types && types[id]) || null;
	};

	// another package's declarations, from the search data beside its page
	const packages = new Map();
	const package_at = dir => {
		if (!packages.has(dir)) {
			packages.set(dir, fetch(dir + "pkg-data.js")
				.then(r => r.ok ? r.text() : null)
				.then(text => {
					if (!text) {
						return null;
					}
					const pkg = Object.values(new Function(text + "\nreturn odin_pkg_data;")().packages)[0];
					return {name: pkg.name, entities: new Map(pkg.entities.map(e => [e.name, e]))};
				})
				.catch(() => null));
		}
		return packages.get(dir);
	};

	const KINDS = {c: "constant", v: "variable", t: "type", p: "procedure", g: "procedure group", b: "built-in"};
	const escape = text => text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

	// a type's definition; for anything else in another package, what it is and its first sentence
	const preview_of = async href => {
		const url = new URL(href, location.href);
		const dir = url.pathname.replace(/\/?$/, "/");
		if (dir === location.pathname.replace(/\/?$/, "/")) {
			return definition_of(href);
		}
		const pkg = await package_at(dir);
		const entity = pkg && pkg.entities.get(decodeURIComponent(url.hash.slice(1)));
		if (!entity) {
			return null;
		}
		const definition = entity.kind === "t" ? await definition_of(href) : null;
		return definition || `${escape(pkg.name)}.${escape(entity.name)}  <span class="comment">// ${KINDS[entity.kind] || ""}</span>` +
			(entity.d ? `\n<span class="comment doc-value-wrap">// ${escape(entity.d)}</span>` : "");
	};

	const hide = () => {
		clearTimeout(timer);
		current = null;
		if (popover) {
			popover.hidden = true;
		}
	};

	const show = async (key, rect_of, html_of, beside = false) => {
		const html = await html_of();
		if (!html || current !== key) {
			return;
		}
		if (!popover) {
			popover = document.createElement("div");
			popover.className = "odin-type-preview";
			popover.setAttribute("role", "tooltip");
			popover.appendChild(document.createElement("pre")).className = "doc-code";
			document.body.appendChild(popover);
		}
		const pre = popover.firstElementChild;
		pre.innerHTML = html;
		pre.style.maxHeight = "";
		popover.hidden = false;

		// always wholly in view: below the navbar, within the window, and no taller than it
		const navbar = document.querySelector(".odin-menu");
		const top = Math.max(0, navbar ? navbar.getBoundingClientRect().bottom : 0) + 8;
		const bottom = window.innerHeight - 8;
		if (popover.offsetHeight > bottom - top) {
			pre.style.maxHeight = (bottom - top) + "px";
		}
		pre.classList.toggle("cut-off", pre.scrollHeight > pre.clientHeight);

		const r = rect_of();
		const width = document.documentElement.clientWidth;
		let x, y;
		if (beside && r.left - popover.offsetWidth - 12 >= 8) {
			// to the left of the Contents panel, rather than over the list being read
			x = r.left - popover.offsetWidth - 12;
			y = r.top - 8;
		} else {
			x = r.left;
			y = r.bottom + 6;
			if (y + popover.offsetHeight > bottom) {
				y = r.top - 6 - popover.offsetHeight;
			}
		}
		x = Math.max(8, Math.min(x, width - popover.offsetWidth - 8));
		y = Math.max(top, Math.min(y, bottom - popover.offsetHeight));
		popover.style.left = (window.scrollX + x) + "px";
		popover.style.top  = (window.scrollY + y) + "px";
	};

	// types in signatures, links to any declaration on this page from the docs, the Contents and the Index,
	// and links from the docs to other packages' declarations
	const in_list = link => link.closest("#TableOfContents, #pkg-index");
	const link_of = ev => {
		const link = ev.target.closest && ev.target.closest("a[href]");
		if (!link || link.closest(".odin-type-preview")) {
			return null;
		}
		if (link.matches("pre.doc-code a.code-typename")) {
			return link;
		}
		if (!in_list(link) && (!link.closest(".documentation") || link.closest("h3"))) {
			return null;
		}
		const url = new URL(link.href, location.href);
		if (!url.hash) {
			return null;
		}
		const dir = url.pathname.replace(/\/?$/, "/");
		if (dir !== location.pathname.replace(/\/?$/, "/")) {
			// a package's page, not a collection's or the home page
			return url.origin === location.origin && dir.split("/").length > 3 ? link : null;
		}
		const target = document.getElementById(decodeURIComponent(url.hash.slice(1)));
		if (target && target.matches(".doc-dense tr")) {
			return link.closest("tr") === target ? null : link;
		}
		if (!target || !target.matches(".pkg-entity > h3") || link.closest(".pkg-entity") === target.parentElement) {
			return null;
		}
		return link;
	};
	const show_link = link => show(link, () => link.getBoundingClientRect(), () => preview_of(link.getAttribute("href")), !!link.closest("#TableOfContents"));
	document.addEventListener("mouseover", ev => {
		const link = link_of(ev);
		if (link && link !== current && !link.closest(".odin-type-preview")) {
			current = link;
			clearTimeout(timer);
			// longer in the lists, so running the mouse down one doesn't flash a preview for each
			timer = setTimeout(() => show_link(link), in_list(link) ? 450 : 250);
		}
	});
	document.addEventListener("mouseout", ev => {
		const link = link_of(ev);
		if (link && !link.contains(ev.relatedTarget)) {
			hide();
		}
	});
	document.addEventListener("focusin", ev => {
		const link = link_of(ev);
		if (link) {
			current = link;
			show_link(link);
		}
	});
	document.addEventListener("focusout", ev => {
		if (link_of(ev)) {
			hide();
		}
	});
	document.addEventListener("keydown", ev => {
		if (ev.key === "Escape") {
			hide();
		}
	});
	// any scroll, the Contents panel's included
	document.addEventListener("scroll", hide, {passive: true, capture: true});

	// Names in examples, e.g. `strings.split`, look as they did, but hovering one shows what it is,
	// and Ctrl+click (Cmd+click) goes to it; a plain click still selects text
	const here = location.pathname.replace(/\/?$/, "/");
	const mac = document.body.classList.contains("os-macos");

	// `import "core:strings"` and `import str "core:strings"` in the example name its packages
	const imports = new WeakMap();
	const imports_of = code => {
		if (!imports.has(code)) {
			const found = new Map();
			for (const m of code.textContent.matchAll(/^\s*import\s+(?:(\w+)\s+)?"(\w+):([^"]+)"/gm)) {
				found.set(m[1] || m[3].split("/").pop(), `/${m[2]}/${m[3]}/`);
			}
			imports.set(code, found);
		}
		return imports.get(code);
	};

	const name_at = (x, y) => {
		const at = text_at_point(x, y);
		if (!at) {
			return null;
		}
		const [node, offset] = at;
		const code = node.parentElement && node.parentElement.closest("pre > code");
		if (!code || !code.closest(".documentation") || node.parentElement.closest(".hljs-comment, .hljs-string")) {
			return null;
		}
		const text = node.data;
		let start = offset, end = offset;
		while (start > 0 && /[\w.]/.test(text[start - 1])) {
			start -= 1;
		}
		while (end < text.length && /[\w.]/.test(text[end])) {
			end += 1;
		}
		const parts = text.slice(start, end).split(".");
		if (parts.length < 2 || !/^[A-Za-z_]\w*$/.test(parts[0]) || !/^[A-Za-z_]\w*$/.test(parts[1])) {
			return null;
		}
		const range = new Range();
		range.setStart(node, start);
		range.setEnd(node, start + parts[0].length + 1 + parts[1].length);
		return {code, alias: parts[0], name: parts[1], range, key: `${parts[0]}.${parts[1]}`};
	};

	const resolve = async found => {
		let dir = imports_of(found.code).get(found.alias) || (found.alias === window.odin_pkg_name ? here : null);
		if (!dir) {
			// otherwise a core package, unless the example declares it, as in `sb := strings.builder_make()`
			if (new RegExp(`\\b${found.alias}\\s*(:=|:|,)`).test(found.code.textContent)) {
				return null;
			}
			dir = `/core/${found.alias}/`;
		}
		if (dir === here) {
			const h3 = document.getElementById(found.name);
			if (!h3 || !h3.matches(".pkg-entity > h3")) {
				return null;
			}
			return {href: `#${found.name}`, html: () => definition_of(`#${found.name}`)};
		}
		const pkg = await package_at(dir);
		if (!pkg || !pkg.entities.has(found.name)) {
			return null;
		}
		const href = `${dir}#${found.name}`;
		return {href, html: () => preview_of(href)};
	};

	let hovered = null;
	let scheduled = false;
	document.addEventListener("mousemove", ev => {
		const in_code = ev.target.closest && ev.target.closest(".documentation pre > code");
		if (scheduled || (!in_code && !hovered)) {
			return;
		}
		scheduled = true;
		requestAnimationFrame(() => {
			scheduled = false;
			const found = in_code ? name_at(ev.clientX, ev.clientY) : null;
			if (found && hovered && found.key === hovered.key) {
				return;
			}
			if (hovered && current === hovered) {
				hide();
			}
			hovered = found;
			if (!found) {
				return;
			}
			current = found;
			clearTimeout(timer);
			timer = setTimeout(async () => {
				const target = await resolve(found);
				if (target && current === found) {
					const hint = `\n<span class="comment">// ${mac ? "\u2318" : "Ctrl"}+click to go to it</span>`;
					show(found, () => found.range.getBoundingClientRect(), async () => (await target.html()) + hint);
				}
			}, 250);
		});
	});
	// a value too long to show at the end of its line, where the box would cut it off, shows here instead
	const measure = document.createElement("canvas").getContext("2d");
	document.addEventListener("mouseover", ev => {
		const span = ev.target.closest && ev.target.closest("pre.doc-code .doc-value, table.doc-dense .doc-value");
		if (!span || span === current || span.closest(".odin-type-preview")) {
			return;
		}
		const pre = span.closest("pre, td");
		const style = getComputedStyle(pre);
		measure.font = `${style.fontSize} ${style.fontFamily}`;
		const room = pre.getBoundingClientRect().right - parseFloat(style.paddingRight) - span.getBoundingClientRect().right;
		const long = measure.measureText(` // ${span.dataset.value}`).width > room;
		span.classList.toggle("doc-value-long", long);
		if (long) {
			current = span;
			clearTimeout(timer);
			show(span, () => span.getBoundingClientRect(), () => `<span class="comment doc-value-wrap">// ${escape(span.dataset.value)}</span>`);
		}
	});
	document.addEventListener("mouseout", ev => {
		const span = ev.target.closest && ev.target.closest("pre.doc-code .doc-value, table.doc-dense .doc-value");
		if (span && span === current && !span.contains(ev.relatedTarget)) {
			hide();
		}
	});

	document.addEventListener("click", async ev => {
		if (!(ev.ctrlKey || ev.metaKey)) {
			return;
		}
		const found = name_at(ev.clientX, ev.clientY);
		if (!found) {
			return;
		}
		ev.preventDefault();
		const target = await resolve(found);
		if (target) {
			location.href = new URL(target.href, location.href).href;
		}
	});
}

var odin_pkg_name;

let odin_search = document.getElementById("odin-search");
if (odin_search) {
	function getElementsByClassNameArray(x) {
		return Array.from(document.getElementsByClassName(x));
	}

	function escape_html(text) {
		return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
	}

	function strcmp(a, b) {
		return ((a == b) ? 0 : ((a > b) ? 1 : -1));
	}
	function get_key_string(ev) {
		let name;
		let ignore_shift = false;
		switch (ev.which) {
		case 13:
			name = "Enter";
			break;
		case 27:
			name = "Esc";
			break;
		case 38:
			name = "Up";
			break;
		case 40:
			name = "Down";
			break;
		default:
			ignore_shift = true;
			name = ev.key != null ? ev.key : String.fromCharCode(ev.charCode || ev.keyCode);
		}
		if (!ignore_shift && ev.shiftKey) name = "Shift+" + name;
		if (ev.altKey) name = "Alt+" + name;
		if (ev.ctrlKey) name = "Ctrl+" + name;
		return name;
	}
	function clamp(x, lo, hi) {
		if (x < lo) {
			return lo;
		} else if (x > hi) {
			return hi;
		}
		return x;
	}

	// ---------------------------------------------------------------------
	// Matching
	//
	// A query is split into whitespace/dot separated tokens ("os read" and
	// "os.read" both become ["os", "read"]). Every token must match an entity
	// for it to appear, and each token is scored by the best of three
	// strategies, strongest signal first:
	//
	//   1. substring  - the token appears verbatim; graded by where/how well
	//   2. acronym    - the token maps onto the initials of the words / camel
	//                    humps of the name (e.g. "rai" -> resource_acquisition_is)
	//   3. fuzzy      - the token is a scattered subsequence (typo tolerant)
	//
	// Each matcher returns { score, indices } where `indices` are positions in
	// the full name that were matched, used purely for highlighting. Matching
	// never builds any HTML; formatting happens later and only for the handful
	// of results actually displayed.
	// ---------------------------------------------------------------------

	function is_sep(c)   { return c === '_' || c === ' ' || c === '.' || c === '/' || c === ':'; }
	function is_lower(c) { return c >= 'a' && c <= 'z'; }
	function is_upper(c) { return c >= 'A' && c <= 'Z'; }
	function is_digit(c) { return c >= '0' && c <= '9'; }

	// Index in `full` where the declaration name begins, i.e. just past the
	// single dot that separates the package from the name ("pkg.name"). For
	// built-ins (no dot) the whole string is the name.
	function name_start_of(full) {
		let dot = full.indexOf('.');
		return dot < 0 ? 0 : dot + 1;
	}

	// Graded verbatim-substring match. Rather than giving every hit the same
	// flat score (which forced the sort onto an alphabetical tiebreak and
	// buried the obvious matches), grade it by *where* and *how well* it lands.
	function substring_match(str, token) {
		const lc_str = str.toLowerCase();
		const lc_tok = token.toLowerCase();
		let first = lc_str.indexOf(lc_tok);
		if (first < 0) {
			return null;
		}

		const dot_idx    = str.indexOf('.');
		const name_start = dot_idx < 0 ? 0 : dot_idx + 1;
		const name_len   = str.length - name_start;
		const pkg_len    = dot_idx < 0 ? 0 : dot_idx;

		const BASE              = 100000; // keep every substring hit above any acronym/fuzzy hit
		const NAME_BONUS        =   4000; // match falls in the declaration name, not the package
		const WORD_START_BONUS  =   2000; // match begins at a word boundary ( _ . space or start )
		const NAME_PREFIX_BONUS =   2000; // match is the very start of the name
		const EXACT_NAME_BONUS  =  10000; // the name is exactly the token
		const CAMEL_BONUS_S     =   1000; // match begins on a camelCase hump
		const CASE_BONUS        =    250; // matched with the exact case the user typed
		const COVERAGE_WEIGHT   =   3000; // reward hits that cover more of the segment they land in

		let best_score = -Infinity;
		let best_idx   = first;

		// The first occurrence is not always the most relevant (a hit in the
		// package name loses to one in the declaration name), so score every
		// occurrence and keep the best.
		for (let i = first; i >= 0; i = lc_str.indexOf(lc_tok, i + 1)) {
			const end         = i + token.length;
			const in_name     = i >= name_start;
			const char_before = i > 0 ? str.charAt(i - 1) : '.';
			const word_start  = i === name_start || is_sep(char_before);
			const camel       = i > 0 && (is_lower(str.charAt(i - 1)) || is_digit(str.charAt(i - 1))) && is_upper(str.charAt(i));
			const exact_name  = in_name && i === name_start && end === str.length;

			let s = BASE;
			if (in_name)                     s += NAME_BONUS;
			if (word_start)                  s += WORD_START_BONUS;
			if (in_name && i === name_start) s += NAME_PREFIX_BONUS;
			if (camel)                       s += CAMEL_BONUS_S;
			if (exact_name)                  s += EXACT_NAME_BONUS;
			if (str.substring(i, end) === token) s += CASE_BONUS;

			// Coverage: how much of the segment it lands in the match fills
			// (clamped to 1 for tokens that straddle a boundary).
			const seg = in_name ? name_len : (pkg_len || str.length);
			s += Math.round(Math.min(token.length / Math.max(seg, 1), 1) * COVERAGE_WEIGHT);

			// Gently prefer shorter identifiers and earlier match positions.
			s -= Math.min(str.length, 100);
			s -= Math.min(Math.max(i - name_start, 0), 50);

			if (s > best_score) {
				best_score = s;
				best_idx   = i;
			}
		}

		let indices = new Array(token.length);
		for (let k = 0; k < token.length; k++) {
			indices[k] = best_idx + k;
		}
		return {score: best_score, indices: indices};
	}

	// Acronym / initialism match: the token letters map, in order, onto the
	// starts of words (after a separator or on a camelCase / digit hump).
	function acronym_match(str, token) {
		if (token.length < 2) {
			return null; // a single-letter "acronym" is noise
		}
		const lc_tok      = token.toLowerCase();
		const name_start  = name_start_of(str);

		let ti      = 0;
		let indices = [];
		let anchored_at_name_start = false;

		for (let i = 0; i < str.length && ti < token.length; i++) {
			const c    = str.charAt(i);
			const prev = i > 0 ? str.charAt(i - 1) : '';
			const word_start =
				i === 0 ||
				is_sep(prev) ||
				(is_upper(c) && (is_lower(prev) || is_digit(prev))) ||
				(is_digit(c) && !is_digit(prev) && !is_sep(prev));

			if (word_start && c.toLowerCase() === lc_tok.charAt(ti)) {
				if (ti === 0 && i === name_start) {
					anchored_at_name_start = true;
				}
				indices.push(i);
				ti += 1;
			}
		}

		if (ti !== token.length) {
			return null;
		}

		const ACRONYM_BASE = 50000; // below any substring hit, above any fuzzy hit
		let s = ACRONYM_BASE;
		if (indices[0] >= name_start)  s += 2000; // initials taken from the name, not the package
		if (anchored_at_name_start)    s += 2000; // ...and starting at the name's first word
		// Tighter runs (fewer skipped words) are better.
		s -= Math.min(indices[indices.length - 1] - indices[0], 100);
		s -= Math.min(str.length, 100);
		return {score: s, indices: indices};
	}

	// Fuzzy subsequence match (typo tolerant fallback).
	function fuzzy_match(str, pattern) {
		// Score consts
		const ADJACENCY_BONUS            =  5; // bonus for adjacent matches
		const SEPARATOR_BONUS            = 10; // bonus if match occurs after a separator
		const CAMEL_BONUS                = 10; // bonus if match is uppercase and prev is lower
		const SEEN_DOT_BONUS             = 10;
		const LEADING_LETTER_PENALTY     = -3; // penalty applied for every letter in str before the first match
		const MAX_LEADING_LETTER_PENALTY = -9; // maximum penalty for leading letters
		const UNMATCHED_LETTER_PENALTY   = -1; // penalty for every letter that doesn't matter

		// Loop variables
		let score          = 0;
		let pattern_idx    = 0;
		let pattern_length = pattern.length;
		let str_idx        = 0;
		let str_length     = str.length;
		let prev_matched   = false;
		let prev_lower     = false;
		let prev_separator = true;  // true so if first letter match gets separator bonus

		// Use "best" matched letter if multiple string letters match the pattern
		let best_letter       = null;
		let best_lower        = null;
		let best_letter_idx   = null;
		let best_letter_score = 0;
		let seen_dot = false;

		let matched_indices = [];

		// Loop over string
		while (str_idx != str_length) {
			let pattern_char = pattern_idx != pattern_length ? pattern.charAt(pattern_idx) : null;
			let str_char     = str.charAt(str_idx);

			let pattern_lower = pattern_char != null ? pattern_char.toLowerCase() : null;
			let str_lower     = str_char.toLowerCase();
			let str_upper     = str_char.toUpperCase();

			let next_match = pattern_char && pattern_lower == str_lower;
			let rematch    = best_letter && best_lower == str_lower;

			let advanced       = next_match && best_letter;
			let pattern_repeat = best_letter && pattern_char && best_lower == pattern_lower;
			if (advanced || pattern_repeat) {
				score += best_letter_score;
				matched_indices.push(best_letter_idx);
				best_letter = null;
				best_lower = null;
				best_letter_idx = null;
				best_letter_score = 0;
			}

			if (next_match || rematch) {
				let new_score = 0;

				// Apply penalty for each letter before the first pattern match
				// Note: std::max because penalties are negative values. So max is smallest penalty.
				if (pattern_idx == 0) {
					let penalty = Math.max(str_idx * LEADING_LETTER_PENALTY, MAX_LEADING_LETTER_PENALTY);
					score += penalty;
				}

				// Apply bonus for consecutive bonuses
				if (prev_matched) {
					new_score += ADJACENCY_BONUS;
				}

				// Apply bonus for matches after a separator
				if (prev_separator) {
					new_score += SEPARATOR_BONUS;
				}

				// Apply bonus across camel case boundaries. Includes "clever" isLetter check.
				if (prev_lower && str_char == str_upper && str_lower != str_upper) {
					new_score += CAMEL_BONUS;
				}

				// Update patter index IFF the next pattern letter was matched
				if (next_match) {
					pattern_idx += 1;
				}

				// Update best letter in str which may be for a "next" letter or a "rematch"
				if (new_score >= best_letter_score) {

					// Apply penalty for now skipped letter
					if (best_letter != null) {
						score += UNMATCHED_LETTER_PENALTY;
					}

					best_letter = str_char;
					best_lower = best_letter.toLowerCase();
					best_letter_idx = str_idx;
					best_letter_score = new_score;
					if (seen_dot) {
						// Priorities declaration name not package
						best_letter_score += SEEN_DOT_BONUS;
					}
				}

				prev_matched = true;
			} else {
				score += UNMATCHED_LETTER_PENALTY;
				prev_matched = false;
			}

			// Includes "clever" isLetter check.
			prev_lower = str_char == str_lower && str_lower != str_upper;
			if (str_char == '.') {
				seen_dot = true;
			}

			// Match separator.
			//
			// NOTE: the original code advanced `pattern_idx` here on *every*
			// separator in the string, regardless of the pattern. That let a
			// query "complete" simply by consuming enough separators, so
			// patterns that were not really present were reported as matches
			// (e.g. "xyzij" matching "a_b_c_d_e"). That advance has been
			// removed so matching is a correct subsequence test.
			prev_separator = str_char == '_' || str_char == ' ' || str_char == '.';

			str_idx += 1;
		}

		// Apply score for last match
		if (best_letter) {
			score += best_letter_score;
			matched_indices.push(best_letter_idx);
		}

		let matched = pattern_idx == pattern_length;
		if (!matched) {
			return null;
		}
		return {score: score, indices: matched_indices};
	}

	// Best score for a single token against one entity name.
	function match_token(str, token) {
		let best = substring_match(str, token);

		let acr = acronym_match(str, token);
		if (acr && (best === null || acr.score > best.score)) {
			best = acr;
		}

		// Fuzzy is the fallback: only pay for it when nothing stronger matched.
		if (best === null) {
			best = fuzzy_match(str, token);
		}
		return best;
	}

	// An entity matches only if *every* token matches; its score is the sum of
	// the per-token scores and its highlight set is the union of their indices.
	function match_entity(full, tokens) {
		let total       = 0;
		let all_indices = [];
		for (let t = 0; t < tokens.length; t++) {
			let m = match_token(full, tokens[t]);
			if (m === null) {
				return null;
			}
			total += m.score;
			for (let k = 0; k < m.indices.length; k++) {
				all_indices.push(m.indices[k]);
			}
		}
		return {score: total, indices: all_indices};
	}

	// "Buffer->length", as an Objective-C method is called, is "Buffer length" too
	function tokenize(text) {
		return text.replace(/->/g, ".").split(/[\s.]+/).filter(function(t) { return t.length > 0; });
	}

	// Kinds a searcher is most likely to be after, used only to break exact
	// score ties. Lower = higher priority.
	const KIND_RANK = {
		"pkg": -1, // package
		"p": 0, // procedure
		"g": 0, // procedure group
		"t": 1, // type
		"b": 2, // builtin / intrinsic
		"v": 3, // variable
		"c": 4, // constant
	};

	// Incremental filtering: the results for a query are always a subset of the
	// results for any prefix of that query, so when the user is typing forward
	// we only re-rank the previous match set instead of rescanning everything.
	let search_cache = {query: "", entities: null};

	function reset_search_cache() {
		search_cache.query = "";
		search_cache.entities = null;
	}

	function fuzzy_entity_match(entities, search_text) {
		let tokens = tokenize(search_text);
		if (tokens.length === 0) {
			return [];
		}

		let source = entities;
		if (search_cache.entities && search_cache.query && search_text.startsWith(search_cache.query)) {
			source = search_cache.entities;
		}

		let source_length = source.length;
		let results = [];
		for (let i = 0; i < source_length; i++) {
			let entity = source[i];
			let m = match_entity(entity.full, tokens);
			// a package named in full, `png` or `image/png`, comes first
			if (m !== null && entity.kind === "pkg") {
				let query = search_text.trim().toLowerCase();
				if (query === entity.name.toLowerCase() || query === entity.name.slice(entity.name.lastIndexOf("/") + 1).toLowerCase()) {
					m.score += 20000;
				}
			}
			let alt = false;
			if (entity.alt !== undefined) {
				let a = match_entity(entity.alt, tokens);
				if (a !== null && (m === null || a.score > m.score)) {
					m = a;
					alt = true;
				}
			}
			if (m !== null) {
				results.push({
					"entity":  entity,
					"score":   m.score,
					"indices": m.indices,
					"alt":     alt,
				});
			}
		}

		results.sort(function(a, b) {
			if (a.score !== b.score) {
				return b.score - a.score;
			}
			// Tie-break: prefer what isn't deprecated, the more likely kind, then
			// shorter names, then alphabetical order, so equal-scoring ties resolve
			// toward the more probable target instead of whatever happens to sort first.
			if (!a.entity.dep !== !b.entity.dep) {
				return a.entity.dep ? 1 : -1;
			}
			let ka = KIND_RANK[a.entity.kind]; if (ka === undefined) ka = 5;
			let kb = KIND_RANK[b.entity.kind]; if (kb === undefined) kb = 5;
			if (ka !== kb) {
				return ka - kb;
			}
			if (a.entity.name.length !== b.entity.name.length) {
				return a.entity.name.length - b.entity.name.length;
			}
			return strcmp(a.entity.name, b.entity.name);
		});

		search_cache.query = search_text;
		search_cache.entities = results.map(function(r) { return r.entity; });
		return results;
	}

	// Wrap the matched index ranges of full[from,to) in <b>, coalescing runs of
	// adjacent matched characters into a single span.
	function highlight_range(full, idx_set, from, to) {
		let out = "";
		let i = from;
		while (i < to) {
			if (idx_set.has(i)) {
				let j = i;
				while (j < to && idx_set.has(j)) j++;
				out += "<b>" + full.substring(i, j) + "</b>";
				i = j;
			} else {
				let j = i;
				while (j < to && !idx_set.has(j)) j++;
				out += full.substring(i, j);
				i = j;
			}
		}
		return out;
	}

	{
		const IS_PACKAGE_PAGE = odin_search.className == "odin-search-package";
		const IS_GLOBAL = odin_search.className == "odin-search-all";
		const IS_PACKAGE_BUILTIN = IS_PACKAGE_PAGE && odin_pkg_name == "builtin";

		let entities = [];
		function add_entity(odin_pkg_name, e) {
			if (odin_pkg_name == "") {
				e.pkg = "builtin";
				e.full = e.name;
			} else {
				e.pkg = odin_pkg_name;
				e.full = odin_pkg_name+'.'+e.name; // add full name
			}
			entities.push(e);
		}

		// A binding is also found by the C name it links to, "SDL_CreateWindow" for CreateWindow.
		// An Objective-C class is found by its own name, "MTLBuffer" for Buffer,
		// and so are its methods, "MTLBuffer.length" for Buffer_length.
		function add_alt_names(pkg_name, pkg_entities) {
			let classes = null;
			for (let j = 0; j < pkg_entities.length; j++) {
				let e = pkg_entities[j];
				if (e.c !== undefined) {
					e.alt = pkg_name+'.'+e.c;
				}
				if (e.objc !== undefined) {
					classes = classes || new Map();
					classes.set(e.name, e.objc);
					e.alt = pkg_name+'.'+e.objc;
				}
			}
			if (classes === null) {
				return;
			}
			for (let j = 0; j < pkg_entities.length; j++) {
				let e = pkg_entities[j];
				let sep = e.name.indexOf('_');
				let objc = (e.kind == "p" || e.kind == "g") && sep > 0 ? classes.get(e.name.substring(0, sep)) : undefined;
				if (objc !== undefined) {
					e.alt = pkg_name+'.'+objc+'.'+e.name.substring(sep + 1);
				}
			}
		}

		if (IS_PACKAGE_PAGE) {
			let pkg_name = odin_pkg_name;
			let entities = odin_pkg_data.packages[pkg_name].entities;
			add_alt_names(pkg_name, entities);
			for (let j = 0; j < entities.length; j++) {
				add_entity(pkg_name, entities[j]);
			}
			if (IS_PACKAGE_BUILTIN) {
				pkg_name = "runtime";
				let entities = odin_pkg_data.packages[pkg_name].entities;
				for (let j = 0; j < entities.length; j++) {
					let entity = entities[j];
					if (entity.builtin) {
						add_entity(pkg_name, entity);
					}
				}
			}
		} else {
			let all_packages = Object.entries(odin_pkg_data.packages);
			for (let i = 0; i < all_packages.length; i++) {
				let [pkg_name, pkg] = all_packages[i];
				let entities = pkg.entities;
				add_alt_names(pkg_name, entities);
				for (let j = 0; j < entities.length; j++) {
					let e = entities[j];
					if (e.builtin) {
						let be = Object.assign({}, e);
						add_entity("", be);
					}
					add_entity(pkg_name, e);
				}
			}
			// e.g. `core:image/png`, which leads to the package's page
			for (let i = 0; i < all_packages.length; i++) {
				let [pkg_name, pkg] = all_packages[i];
				let parts = pkg.path.split("/");
				let path = parts.slice(parts.indexOf(pkg.collection) + 1).join("/");
				if (path !== "") {
					entities.push({kind: "pkg", name: path, pkg: pkg_name, full: `${pkg.collection}:${path}`, path: pkg.path});
				}
			}
		}

		let odin_search_results = document.getElementById("odin-search-results");
		let odin_search_time    = document.getElementById("odin-search-time");
		let odin_search_filter  = document.getElementById("odin-search-filter");
		let curr_search_index   = -1;
		let curr_search_value   = "";

		let pkg_entities = getElementsByClassNameArray("pkg-entity");
		let dense_rows = [...document.querySelectorAll(".doc-dense tbody > tr")];
		let pkg_headers = getElementsByClassNameArray("pkg-header");
		let pkg_top = document.getElementById("pkg-top");

		// Accessibility: expose the search box + results as an ARIA combobox
		// driving a listbox, so screen readers announce the active result.
		odin_search.setAttribute("role", "combobox");
		odin_search.setAttribute("aria-autocomplete", "list");
		odin_search.setAttribute("aria-expanded", "false");
		odin_search.setAttribute("aria-haspopup", "listbox");
		if (odin_search_results) {
			odin_search_results.setAttribute("role", "listbox");
			if (!odin_search_results.id) {
				odin_search_results.id = "odin-search-results";
			}
			odin_search.setAttribute("aria-controls", odin_search_results.id);
		}


		if (odin_search_filter) {
			odin_search_filter.onclick = function(ev) {
				clear_odin_search_doms();
				odin_search.value = '';
			};
		}


		function move_search_cursor(dir) {
			if (curr_search_index < 0 || curr_search_index >= odin_search_results.children.length) {
				if (dir > 0)  {
					curr_search_index = dir-1;
				} else if (dir < 0) {
					curr_search_index = dir+odin_search_results.children.length;
				}
			} else {
				curr_search_index += dir;
			}
			curr_search_index = clamp(curr_search_index, 0, odin_search_results.children.length-1);
			draw_search_cursor();
		}
		function draw_search_cursor() {
			let active_id = "";
			for (let i = 0; i < odin_search_results.children.length; i++) {
				let li = odin_search_results.children[i];
				if (curr_search_index === i) {
					li.classList.add("selected");
					li.setAttribute("aria-selected", "true");
					active_id = li.id || "";
					if (li.scrollIntoView) {
						li.scrollIntoView({block: "nearest"});
					}
				} else {
					li.classList.remove("selected");
					li.setAttribute("aria-selected", "false");
				}
			}
			odin_search.setAttribute("aria-activedescendant", active_id);
		}

		function clear_odin_search_doms() {
			reset_search_cache();
			odin_search_results.innerHTML = '';
			odin_search_time.innerHTML = '';
			odin_search.setAttribute("aria-expanded", "false");
			odin_search.setAttribute("aria-activedescendant", "");
			for (let i = 0; i < pkg_entities.length; i++) {
				let pkg_entity = pkg_entities[i];
				if (pkg_entity) {
					pkg_entity.style.display = null;
					pkg_entity.style.order = null;
				}
			}
			for (let i = 0; i < pkg_headers.length; i++) {
				let pkg_header = pkg_headers[i];
				if (pkg_header) {
					pkg_header.style.display = null;
				}
			}
			for (let row of dense_rows) {
				row.style.display = null;
			}
			if (pkg_top) {
				pkg_top.style.display = null;
			}
		}

		// `:Builder` finds the declarations whose signature or definition mentions the type `Builder`,
		// the declaration itself first, then procedures; lowercase matches either case
		let signatures = null;
		function type_match(type) {
			if (!/^[A-Za-z_][\w.]*$/.test(type)) {
				return [];
			}
			if (!signatures) {
				signatures = [];
				for (let i = 0; i < pkg_entities.length; i++) {
					let h3 = pkg_entities[i].querySelector(":scope > h3");
					let pre = pkg_entities[i].querySelector(":scope > div > pre.doc-code");
					if (!h3 || !pre) {
						continue;
					}
					let text = "";
					for (let node of pre.childNodes) {
						if (!(node.nodeType === Node.ELEMENT_NODE && node.classList.contains("copy-code"))) {
							text += node.textContent;
						}
					}
					signatures.push([h3.id, text]);
				}
				for (let row of dense_rows) {
					let code = row.id && row.querySelector("td > code");
					if (code) {
						signatures.push([row.id, code.textContent]);
					}
				}
			}
			let any_case = !/[A-Z]/.test(type);
			let re = new RegExp(`(?<![\\w])${type.replace(/\./g, "\\.")}(?![\\w])`, any_case ? "i" : "");
			let by_name = new Map(entities.map(e => [e.name, e]));
			let found = [];
			for (let [name, text] of signatures) {
				let entity = by_name.get(name);
				if (entity && re.test(text)) {
					let itself = any_case ? name.toLowerCase() === type.toLowerCase() : name === type;
					let score = itself ? 2 : (entity.kind === "p" || entity.kind === "g") ? 1 : 0;
					found.push({"entity": entity, "score": score, "indices": []});
				}
			}
			found.sort((a, b) => b.score - a.score || strcmp(a.entity.name, b.entity.name));
			return found;
		}

		function odin_search_input(ev) {
			let search_text = odin_search.value.trim();
			if (curr_search_value == search_text) {
				return;
			}
			curr_search_value = search_text;
			if (!search_text) {
				clear_odin_search_doms();
				return;
			}

			curr_search_index = -1; // reset the search index as new text has been found

			let start_time = performance.now();

			let results = IS_PACKAGE_PAGE && search_text.startsWith(":") ? type_match(search_text.slice(1).trim()) : fuzzy_entity_match(entities, search_text);
			if (!results.length) {
				clear_odin_search_doms();
				return;
			}

			let results_found = results.length;
			let MAX_RESULTS_LENGTH = 32;
			let results_length = results.length;

			if (IS_PACKAGE_PAGE && odin_search_filter.checked) {
				let result_map = {};
				for (let result_idx = 0; result_idx < results_length; result_idx++) {
					let result = results[result_idx];
					let entity = result.entity;
					result_map[entity.name] = result;
				}

				if (results_length) {
					pkg_top.style.display = 'none';
					for (let i = 0; i < pkg_headers.length; i++) {
						pkg_headers[i].style.display = 'none';
					}
				}

				for (let i = 0; i < pkg_entities.length; i++) {
					let pkg_entity = pkg_entities[i];
					let name = pkg_entity.getElementsByTagName('h3')[0].id;
					let result = result_map[name];
					if (result) {
						pkg_entity.style.display = null;
						pkg_entity.style.order = -result.score;
					} else {
						pkg_entity.style.display = 'none';
						pkg_entity.style.order = null;
					}

				}
				for (let row of dense_rows) {
					row.style.display = row.id && result_map[row.id] ? null : 'none';
				}
			} else {
				// limit the results (only the displayed results are formatted)
				results_length = Math.min(results_length, MAX_RESULTS_LENGTH);

				let list_contents = [];
				for (let result_idx = 0; result_idx < results_length; result_idx++) {
					let result = results[result_idx];
					let entity = result.entity;

					if (entity.kind === "pkg") {
						list_contents.push(`<li id="odin-search-result-${result_idx}" role="option" aria-selected="false" data-path="${entity.path}">`);
						list_contents.push(`<div class="kind kind-pkg" title="package">package</div>`);
						list_contents.push(`<div><a href="${entity.path}">${highlight_range(entity.full, new Set(result.indices), 0, entity.full.length)}</a></div></li>\n`);
						continue;
					}

					let full = result.alt ? entity.alt : entity.full;
					let idx_set = new Set(result.indices);
					let dot = full.indexOf('.');

					let is_builtin = false;
					let formatted_pkg = null;
					let formatted_name = "";
					if (dot >= 0) {
						formatted_pkg  = highlight_range(full, idx_set, 0, dot);
						formatted_name = highlight_range(full, idx_set, dot + 1, full.length);
					} else {
						is_builtin = entity.pkg == "builtin" || entity.pkg == "intrinsics" || entity.pkg == "runtime";
						formatted_name = highlight_range(full, idx_set, 0, full.length);
					}
					if (result.alt) {
						formatted_name = `${entity.name}&nbsp;<span class="odin-search-alt">${formatted_name}</span>`;
					}
					if (entity.dep) {
						formatted_name = `<s>${formatted_name}</s>`;
					}

					let pkg_path = odin_pkg_data.packages[entity.pkg].path;
					let full_path = `${pkg_path}/#${entity.name}`;

					list_contents.push(`<li id="odin-search-result-${result_idx}" role="option" aria-selected="false" data-path="${full_path}">`);
					// list_contents.push(`${result.score}&mdash;`);

					const entity_kind_map = {
						"c": ["const", "constant"],
						"v": ["var",   "variable"],
						"t": ["type",  "type"],
						"p": ["proc",  "procedure"],
						"g": ["group", "procedure group"],
						"b": (entity.pkg == "intrinsics") ? ["intrinsic", "intrinsic"] : ["builtin", "built-in"],
					};

					let [label, entity_kind] = entity_kind_map[entity.kind];
					let kind_class = `kind-${entity.kind}`;
					if (is_builtin && entity.kind !== "b") {
						label = "builtin";
						kind_class = "kind-b";
						entity_kind = `built-in ${entity_kind}`;
					}
					if (entity.dep) {
						kind_class += " deprecated";
						entity_kind = `deprecated ${entity_kind}`;
					}
					list_contents.push(`<div class="kind ${kind_class}" title="${entity_kind}">${label}</div>`);

					let use = entity.use ? ` <a class="odin-search-use" href="${entity.use_url}">\u2192 ${escape_html(entity.use)}</a>` : "";
					if (formatted_pkg !== null && (!IS_PACKAGE_PAGE || entity.pkg != odin_pkg_name)) {
						let collection = IS_GLOBAL ? `<span class="odin-search-collection">${odin_pkg_data.packages[entity.pkg].collection}:</span>` : "";
						list_contents.push(`<div><a href="${pkg_path}">${collection}${formatted_pkg}</a>.<a href="${full_path}">${formatted_name}</a>${use}</div>`);
					} else {
						list_contents.push(`<div><a href="${full_path}">${formatted_name}</a>${use}</div>`);
					}

					// its first sentence, on package pages, and only where there is room for it
					if (entity.d !== undefined) {
						list_contents.push(`<div class="summary">${escape_html(entity.d)}</div>`);
					}

					list_contents.push(`</li>\n`);
				}

				odin_search_results.innerHTML = list_contents.join('');
				odin_search.setAttribute("aria-expanded", "true");
			}

			let end_time = performance.now();
			let diff = (end_time - start_time).toFixed(1);

			odin_search_time.innerHTML = `<p>Time to search ${diff} milliseconds (found ${results_found}/${entities.length}, displaying ${results_length})</p>`;

			return;
		}

		// Coalesce rapid keystrokes: run the search at most once per animation
		// frame so typing never blocks on a heavy re-scan.
		let search_raf = 0;
		function request_search() {
			if (search_raf) {
				return;
			}
			search_raf = requestAnimationFrame(function() {
				search_raf = 0;
				odin_search_input(null);
			});
		}
		function flush_search() {
			if (search_raf) {
				cancelAnimationFrame(search_raf);
				search_raf = 0;
				odin_search_input(null);
			}
		}

		let url_parameters = new URLSearchParams(window.location.search);
		if (url_parameters.has("q")) {
			let search_query = url_parameters.get("q");
			odin_search.value = search_query.trim();
			odin_search_input(null);
		} else if (window.odin_not_found) {
			// what the missing page was most likely about
			let parts = location.pathname.split("/").filter(part => part !== "" && part !== "index.html");
			if (parts.length > 0) {
				odin_search.value = decodeURIComponent(parts[parts.length - 1]).replace(/\.html$/, "");
				odin_search_input(null);
			}
		}

		odin_search.addEventListener("input", ev => {
			request_search();
			ev.stopPropagation();
		}, false);

		// the search is kept in the address, so it can be shared, and Back after opening a result returns to it
		let address_timer = 0;
		odin_search.addEventListener("input", () => {
			clearTimeout(address_timer);
			address_timer = setTimeout(() => {
				let url = new URL(location.href);
				let query = odin_search.value.trim();
				if (query) {
					url.searchParams.set("q", query);
				} else {
					url.searchParams.delete("q");
				}
				if (url.href !== location.href) {
					history.replaceState(history.state, "", url);
				}
			}, 400);
		});

		odin_search.addEventListener("keydown", ev => {
			if (ev.key === "Enter" && (ev.ctrlKey || ev.metaKey)) {
				flush_search();
				let li = odin_search_results.children[curr_search_index];
				if (li && li.dataset.path) {
					window.open(li.dataset.path, "_blank", "noopener");
				}
				ev.preventDefault();
				ev.stopPropagation();
				return;
			}
			switch (get_key_string(ev)) {
			case "Enter":
				flush_search(); // make sure the list reflects the latest keystroke
				if (0 <= curr_search_index && curr_search_index < odin_search_results.children.length) {
					let li = odin_search_results.children[curr_search_index];
					let path = li.dataset.path;
					if (li.dataset.path) {
						clear_odin_search_doms();
						window.location.href = li.dataset.path;
					}
				}
				break;
			case "Esc":
				curr_search_index = -1;
				draw_search_cursor();
				if (odin_search.value === "") {
					odin_search.blur(); // so j and k move through the page
				}
				break;
			case "Up":
				move_search_cursor(-1);
				ev.preventDefault();
				break;
			case "Down":
				move_search_cursor(+1);
				ev.preventDefault();
				break;
			default:
				break;
			}
			ev.stopPropagation();
			return;
		}, false);
	}

	window.addEventListener("keydown", ev => {
		if ((ev.key === 'k' && (ev.metaKey || ev.ctrlKey)) || ev.key === '/') {
			odin_search.focus();
			ev.preventDefault();
		}
	});
}