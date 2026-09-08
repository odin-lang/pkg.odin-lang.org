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

	function is_sep(c)   { return c === '_' || c === ' ' || c === '.'; }
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

	function tokenize(text) {
		return text.split(/[\s.]+/).filter(function(t) { return t.length > 0; });
	}

	// Kinds a searcher is most likely to be after, used only to break exact
	// score ties. Lower = higher priority.
	const KIND_RANK = {
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
			if (m !== null) {
				results.push({
					"entity":  entity,
					"score":   m.score,
					"indices": m.indices,
				});
			}
		}

		results.sort(function(a, b) {
			if (a.score !== b.score) {
				return b.score - a.score;
			}
			// Tie-break: prefer the more likely kind, then shorter names, then
			// alphabetical order, so equal-scoring ties resolve toward the more
			// probable target instead of whatever happens to sort first.
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
				// limit the results (only the displayed results are formatted)
				results_length = Math.min(results_length, MAX_RESULTS_LENGTH);

				let list_contents = [];
				for (let result_idx = 0; result_idx < results_length; result_idx++) {
					let result = results[result_idx];
					let entity = result.entity;

					let full = entity.full;
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

					let pkg_path = odin_pkg_data.packages[entity.pkg].path;
					let full_path = `${pkg_path}/#${entity.name}`;

					list_contents.push(`<li id="odin-search-result-${result_idx}" role="option" aria-selected="false" data-path="${full_path}">`);
					// list_contents.push(`${result.score}&mdash;`);

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
		}

		odin_search.addEventListener("input", ev => {
			request_search();
			ev.stopPropagation();
		}, false);

		odin_search.addEventListener("keydown", ev => {
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