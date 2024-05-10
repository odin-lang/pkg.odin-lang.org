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

var odin_pkg_name;

let odin_search = document.getElementById("odin-search");
if (odin_search) {
	function getElementsByClassNameArray(x) {
		return Array.from(document.getElementsByClassName(x));
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


	function fuzzy_match(str, pattern) {
		// Score consts
		const ADJACENCY_BONUS            =  5; // bonus for adjacent matches
		const SEPARATOR_BONUS            = 10; // bonus if match occurs after a separator
		const CAMEL_BONUS                = 10; // bonus if match is uppercase and prev is lower
		const SEEN_DOT_BONUS             = 10;
		const LEADING_LETTER_PENALTY     = -3; // penalty applied for every letter in str before the first match
		const MAX_LEADING_LETTER_PENALTY = -9; // maximum penalty for leading letters
		const UNMATCHED_LETTER_PENALTY   = -1; // penalty for every letter that doesn't matter
		const SUBSTRING_BOUNS            = 50;

		if (str.includes(pattern)) {
			let i = str.indexOf(pattern);
			let formatted_str = str.substring(0, i) + '<b>' + str.substring(i, i+pattern.length) + '</b>' + str.substring(i+pattern.length, str.length);
			let score = pattern.length * SUBSTRING_BOUNS;
			if (str.length == pattern.length) {
				score *= 2;
			}
			return [true, score, formatted_str];
		}

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

		// Loop over strings
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
			prev_separator = str_char == '_' || str_char == ' ' || str_char == '.';

			str_idx += 1;
		}

		// Apply score for last match
		if (best_letter) {
			score += best_letter_score;
			matched_indices.push(best_letter_idx);
		}

		// Finish out formatted string after last pattern matched
		// Build formated string based on matched letters
		let formatted_str = "";
		let last_idx = 0;
		let matched_indices_length = matched_indices.length;
		for (let i = 0; i < matched_indices_length; i++) {
			let idx = matched_indices[i];
			formatted_str += str.substring(last_idx, idx) + "<b>" + str.charAt(idx) + "</b>";
			last_idx = idx + 1;
		}
		formatted_str += str.substring(last_idx, str.length);

		let matched = pattern_idx == pattern_length;
		return [matched, score, formatted_str];
	}

	function fuzzy_entity_match(entities, search_text) {
		let entities_length = entities.length;

		let result_idx = 0;
		let results = new Array(entities_length);
		for (let i = 0; i < entities_length; i++) {
			let entity = entities[i];
			let full_name = entity.full;
			let [matched, score, formatted] = fuzzy_match(full_name, search_text);
			if (matched) {
				results[result_idx++] = {
					"entity":    entity,
					"score":     score,
					"formatted": formatted,
				};
			}
		}

		results.length = result_idx;

		results.sort(function(a, b) {
			if (a.score == b.score) {
				return strcmp(a.entity.name, b.entity.name);
			}
			return b.score - a.score;
		});

		return results;
	}

	{
		const IS_PACKAGE_PAGE = odin_search.className == "odin-search-package";
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

		if (IS_PACKAGE_PAGE) {
			let pkg_name = odin_pkg_name;
			let entities = odin_pkg_data.packages[pkg_name].entities;
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
				for (let j = 0; j < entities.length; j++) {
					let e = entities[j];
					if (e.builtin) {
						let be = Object.assign({}, e);
						add_entity("", be);
					}
					add_entity(pkg_name, e);
				}
			}
		}

		let odin_search_results = document.getElementById("odin-search-results");
		let odin_search_time    = document.getElementById("odin-search-time");
		let odin_search_filter  = document.getElementById("odin-search-filter");
		let curr_search_index   = -1;
		let curr_search_value   = "";

		let pkg_entities = getElementsByClassNameArray("pkg-entity");
		let pkg_headers = getElementsByClassNameArray("pkg-header");
		let pkg_top = document.getElementById("pkg-top");


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
			for (let i = 0; i < odin_search_results.children.length; i++) {
				let li = odin_search_results.children[i];
				if (curr_search_index === i) {
					li.classList.add("selected");
				} else {
					li.classList.remove("selected");
				}
			}
		}

		function clear_odin_search_doms() {
			odin_search_results.innerHTML = '';
			odin_search_time.innerHTML = '';
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
			if (pkg_top) {
				pkg_top.style.display = null;
			}
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

			let results = fuzzy_entity_match(entities, search_text);
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
			} else {
				// limit the results
				results_length = Math.min(results_length, MAX_RESULTS_LENGTH);

				let list_contents = [];
				for (let result_idx = 0; result_idx < results_length; result_idx++) {
					let result = results[result_idx];
					let entity = result.entity;
					let formatted_str = result.formatted;

					let pkg_path = odin_pkg_data.packages[entity.pkg].path;

					let full_path = `${pkg_path}/#${entity.name}`;

					list_contents.push(`<li data-path="${full_path}">`);
					// list_contents.push(`${result.score}&mdash;`);

					let is_builtin = false;
					let [formatted_pkg, formatted_name] = [null, ""];
					if (formatted_str.includes(".")) {
						[formatted_pkg, formatted_name] = formatted_str.split(".", 2);
					} else {
						is_builtin = entity.pkg == "builtin" || entity.pkg == "intrinsics" || entity.pkg == "runtime";
						formatted_name = formatted_str;
					}
					if (formatted_pkg !== null && (!IS_PACKAGE_PAGE || entity.pkg != odin_pkg_name)) {
						list_contents.push(`<div><a href="${pkg_path}">${formatted_pkg}</a>.<a href="${full_path}">${formatted_name}</a></div>`);
					} else {
						list_contents.push(`<div><a href="${full_path}">${formatted_name}</a></div>`);
					}

					const entity_kind_map = {
						"c": "constant",
						"v": "variable",
						"t": "type",
						"p": "procedure",
						"g": "procedure&nbsp;group",
						"b": (entity.pkg == "intrinsics") ? "intrinsics" : "builtin",
					};

					let entity_kind = entity_kind_map[entity.kind];
					if (is_builtin) {
						entity_kind = '(built-in)&nbsp;' + entity_kind;
					}

					list_contents.push(`&nbsp;<div class="kind">${entity_kind}</div>`);

					list_contents.push(`</li>\n`);
				}

				odin_search_results.innerHTML = list_contents.join('');
			}

			let end_time = performance.now();
			let diff = (end_time - start_time).toFixed(1);

			odin_search_time.innerHTML = `<p>Time to search ${diff} milliseconds (found ${results_found}/${entities.length}, displaying ${results_length})</p>`;

			return;
		}

		let url_parameters = new URLSearchParams(window.location.search);
		if (url_parameters.has("q")) {
			let search_query = url_parameters.get("q");
			odin_search.value = search_query.trim();
			odin_search_input(null);
		}

		odin_search.addEventListener("input", ev => {
			odin_search_input(ev);
			ev.stopPropagation();
		}, false);

		odin_search.addEventListener("keydown", ev => {
			switch (get_key_string(ev)) {
			case "Enter":
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
