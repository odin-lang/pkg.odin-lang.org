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
				}

				prev_matched = true;
			} else {
				score += UNMATCHED_LETTER_PENALTY;
				prev_matched = false;
			}

			// Includes "clever" isLetter check.
			prev_lower = str_char == str_lower && str_lower != str_upper;
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
		for (const idx of matched_indices) {
			formatted_str += str.substr(last_idx, idx - last_idx) + "<b>" + str.charAt(idx) + "</b>";
			last_idx = idx + 1;
		}
		formatted_str += str.substr(last_idx, str.length - last_idx);

		let matched = pattern_idx == pattern_length;
		return [matched, score, formatted_str];
	}

	function fuzzy_entity_match(entities, search_text) {
		let results = [];
		for (const entity of entities) {
			let full_name = entity.full;
			let [matched, score, formatted] = fuzzy_match(full_name, search_text);
			if (!matched) {
				continue;
			}

			if (full_name.includes(".")) {
				// Weight the name of the entity itself more than the entire thing
				let base_name = full_name.split(".", 2)[1];
				let [base_matched, base_score, _] = fuzzy_match(base_name, search_text);
				if (base_matched) {
					score += base_score;
				}
			}

			results.push({
				"entity":    entity,
				"score":     score,
				"formatted": formatted,
			});
		}

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
		let entities = [];
		if (IS_PACKAGE_PAGE) {
			for (const e of odin_pkg_data.packages[odin_pkg_name].entities) {
				entities.push(e);
			}
		} else {
			for (const [pkg_name, pkg] of Object.entries(odin_pkg_data.packages)) {
				for (const e of pkg.entities) {
					entities.push(e);
				}
			}
		}

		let odin_search_results = document.getElementById("odin-search-results");
		let curr_search_index = -1;
		let curr_search_value = "";


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


		odin_search.addEventListener("input", ev => {
			let search_text = odin_search.value.trim();
			if (curr_search_value == search_text) {
				ev.stopPropagation(); return;
			}
			curr_search_value = search_text;
			if (!search_text) {
				odin_search_results.innerHTML = '';
				ev.stopPropagation(); return;
			}

			curr_search_index = -1; // reset the search index as new text has been found

			let start_time = performance.now();

			let results = fuzzy_entity_match(entities, search_text);
			if (!results.length) {
				odin_search_results.innerHTML = '';
				ev.stopPropagation(); return;
			}

			let results_found = results.length;
			let MAX_RESULTS_LENGTH = 64;
			results.length = Math.min(results.length, MAX_RESULTS_LENGTH);

			let innerHTML = '';
			for (const result of results) {
				let [pkg_name, entity_name] = result.entity.full.split(".", 2);

				let score = result.score;

				let pkg_path = odin_pkg_data.packages[pkg_name].path;

				let [formatted_pkg, formatted_name] = result.formatted.split(".", 2);
				let full_path = `${pkg_path}/#${entity_name}`;
				innerHTML += `<li data-path="${full_path}">`;
				// innerHTML += `${score}&mdash;`;

				if (IS_PACKAGE_PAGE) {
					innerHTML += `<a href="${full_path}">${formatted_name}</a>`;
				} else {
					innerHTML += `<a href="${pkg_path}">${formatted_pkg}</a>.<a href="${full_path}">${formatted_name}</a>`;
				}

				switch (result.entity.kind) {
				case "c": innerHTML += `&nbsp;<span class="kind">constant</span>`;          break;
				case "v": innerHTML += `&nbsp;<span class="kind">variable</span>`;          break;
				case "t": innerHTML += `&nbsp;<span class="kind">type</span>`;              break;
				case "p": innerHTML += `&nbsp;<span class="kind">procedure</span>`;         break;
				case "g": innerHTML += `&nbsp;<span class="kind">procedure group</span>`;   break;
				case "b": innerHTML += `&nbsp;<span class="kind">builtin procedure</span>`; break;
				}

				innerHTML += `</li>\n`;
			}
			let end_time = performance.now();
			let diff = (end_time - start_time).toFixed(1);

			// innerHTML = `<p>Time to search ${diff} milliseconds (found ${results_found})</p>` + innerHTML

			odin_search_results.innerHTML = innerHTML;

			ev.stopPropagation(); return;
		}, false);

		odin_search.addEventListener("keydown", ev => {
			switch (get_key_string(ev)) {
			case "Enter":
				if (0 <= curr_search_index && curr_search_index < odin_search_results.children.length) {
					let li = odin_search_results.children[curr_search_index];
					let path = li.dataset.path;
					odin_search_results.innerHTML = '';
					window.location.href = li.dataset.path;
				}
				break;
			case "Esc":
				move_search_cursor = -1;
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
