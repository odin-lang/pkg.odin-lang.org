"use strict";

var odin_pkg_data;

let odin_search = document.getElementById("odin-search");
if (odin_search) {
	const getElementsByClassNameArray = function(x) {
		return Array.from(document.getElementsByClassName(x));
	};
	const fuzzy_filter = function(hay, s) {
		hay = hay.toLowerCase();
		s = s.toLowerCase();
		var i = 0, n = -1, l;
		for (;l = s[i++];) {
			if (!~(n = hay.indexOf(l, n+1))) {
				return false;
			}
		}
		return true;
	};

	let entities = odin_pkg_data.entities.map(e => e.name);
	let doc_entities = getElementsByClassNameArray("doc-id-link").map(x => x.closest(".pkg-entity")).filter(x => x);

	let pkg_top = document.getElementById("pkg-top");
	let pkg_headers = getElementsByClassNameArray("pkg-header");
	let empty_sections = getElementsByClassNameArray("pkg-empty-section");

	const setAllDisplays = function(v) {
		pkg_top.style.display = v;
		pkg_headers.forEach(x => x.style.display = v);
		empty_sections.forEach(x => x.style.display = v);
	}

	const resetEntities = function() {
		for (const e of doc_entities) {
			e.style.display = null;
			e.style.order = null;
		}
		setAllDisplays(null);
	};

	odin_search.addEventListener("input", ev => {
		if (odin_search.value) {
			let search_text = odin_search.value.trim();

			let results = entities.filter(e => fuzzy_filter(e, search_text));
			if (results.length) {
				setAllDisplays("none");

				let i = 0;
				for (const e of doc_entities) {
					let name = e.getElementsByTagName("h3")[0].id;
					if (results.includes(name)) {
						e.style.display = null;
						e.style.order = i++;
					} else {
						e.style.display = "none";
						e.style.order = null;
					}
				}
			} else {
				resetEntities();
			}
		} else {
			resetEntities();
		}
		ev.stopPropagation();
		return;
	} , false);
}



// LEGACY CRAP SEARCH TO BE REMOVED


let docsearch_data = {
	appId:     "H6XRVBSW5C",
	apiKey:    "43bb20431f8b3e7576dbb757cbab9047",
	indexName: "odin-lang",
	container: "#algolia-search",
	debug:     false,
	hint:      true,
	autocompleteOptions: {
		minLength: 1,
	},
	algoliaOptions: {
		hitsPerPage: 10,
		ignorePlural: true,
	},
};

let search_elem = document.getElementById("algolia-search");
if (search_elem && search_elem.hasAttribute("data-path")) {
	let data_path = search_elem.getAttribute("data-path");
	docsearch_data.transformItems = function(items) {
		return items.filter(function(item) {
			if (item.url.indexOf(data_path) < 0) {
				return false;
			}
			return true;
		});
	};

	docsearch(docsearch_data);
}
