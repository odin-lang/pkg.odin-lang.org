"use strict";

var odin_pkg_name;

let odin_search = document.getElementById("odin-search");
if (odin_search) {
	const getElementsByClassNameArray = function(x) {
		return Array.from(document.getElementsByClassName(x));
	};
	const fuzzy_filter = function(str, pattern) {
		str = str.replace(".", " ").toLowerCase();
		pattern = pattern.replace(".", " ").toLowerCase();

		let i = 0, n = -1, score = 0, l, run = 0;
		for (;l = pattern[i++];) {
			if (!~(n = str.indexOf(l, n+1))) {
				score -= 10;
				run = 0;
			} else {
				run += 1;
				score += run*10;
			}
		}
		if (l) {
			score -= l.length;
		}
		return score;
	};


	if (odin_search.className == "odin-search-all" ||
	    odin_search.className == "odin-search-collection") {
		let entities = [];
		for (let [pkg_name, pkg] of Object.entries(odin_pkg_data.packages)) {
			for (let e of pkg.entities) {
				entities.push(e.full);
			}
		}

		let odin_search_results = document.getElementById("odin-search-results");

		let curr_search_value = "";
		odin_search.addEventListener("input", ev => {
			let search_text = odin_search.value.trim();
			if (curr_search_value != search_text) {
				curr_search_value = search_text;
				if (search_text) {
					let results_e_and_score = entities.map(e => [e, fuzzy_filter(e, search_text)]).filter(v => v[1] >= 0);

					results_e_and_score.sort(function (a, b) {
						return -(a[1] - b[1]);
					});

					let results = results_e_and_score.map(v => v[0]);
					let scores  = results_e_and_score.map(v => v[1]);
					let max_score = Math.max(...scores);
					scores = scores.map(s => max_score-s);

					let MAX_RESULTS_LENGTH = 64;

					if (results.length) {
						results.length = Math.min(results.length, MAX_RESULTS_LENGTH);
						let innerHTML = '';
						innerHTML = '';
						innerHTML += '<ul>\n';
						for (let result of results) {
							let parts = result.split(".", 2);
							let pkg_name = parts[0], entity_name = parts[1];

							let pkg_path = odin_pkg_data.packages[pkg_name].path;

							innerHTML += `<li><a href="${pkg_path}">${pkg_name}</a>.<a href="${pkg_path}/#${entity_name}">${entity_name}</a></li>\n`;
						}
						innerHTML += '</ul>';
						odin_search_results.innerHTML = innerHTML;
					} else {
						odin_search_results.innerHTML = '';
					}
				} else {
					odin_search_results.innerHTML = '';
				}
			}
			ev.stopPropagation();
			return;
		}, false);

	} else if (odin_search.className == "odin-search-package") {

		var pkg_data = odin_pkg_data.packages[odin_pkg_name];

		let entities = pkg_data.entities.map(e => e.name);
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
			for (let e of doc_entities) {
				e.style.display = null;
				e.style.order = null;
			}
			setAllDisplays(null);
		};

		let curr_search_value = "";
		odin_search.addEventListener("input", ev => {
			let search_text = odin_search.value.trim();
			if (curr_search_value != search_text) {
				curr_search_value = search_text;
				if (search_text) {
					let results_e_and_score = entities.map(e => [e, fuzzy_filter(e, search_text)]).filter(v => v[1] >= 0);
					let results = results_e_and_score.map(v => v[0]);
					let scores  = results_e_and_score.map(v => v[1]);
					let max_score = Math.max(...scores);
					scores = scores.map(s => max_score-s);

					if (results.length) {
						setAllDisplays("none");
						for (let e of doc_entities) {
							let name = e.getElementsByTagName("h3")[0].id;
							let idx = results.indexOf(name);
							if (idx >= 0) {
								e.style.display = null;
								// e.style.order = scores[idx];
							} else {
								e.style.display = "none";
								// e.style.order = null;
							}
						}
					} else {
						resetEntities();
					}
				} else {
					resetEntities();
				}
			}
			ev.stopPropagation();
			return;
		}, false);
	}
}
