"use strict";

var odin_pkg_name;

let odin_search = document.getElementById("odin-search");
if (odin_search) {
	function getElementsByClassNameArray(x) {
		return Array.from(document.getElementsByClassName(x));
	}


	const SEQUENTIAL_BONUS = 15; // bonus for adjacent matches
	const SEPARATOR_BONUS = 30; // bonus if match occurs after a separator
	const CAMEL_BONUS = 30; // bonus if match is uppercase and prev is lower
	const FIRST_LETTER_BONUS = 15; // bonus if the first letter is matched

	const LEADING_LETTER_PENALTY = -5; // penalty applied for every letter in str before the first match
	const MAX_LEADING_LETTER_PENALTY = -15; // maximum penalty for leading letters
	const UNMATCHED_LETTER_PENALTY = -1;

	function fuzzyMatch(pattern, str) {
		const recursionCount = 0;
		const recursionLimit = 10;
		const matches = [];
		const maxMatches = 256;

		return fuzzyMatchRecursive(
			pattern,
			str,
			0 /* patternCurIndex */,
			0 /* strCurrIndex */,
			null /* srcMatces */,
			matches,
			maxMatches,
			0 /* nextMatch */,
			recursionCount,
			recursionLimit
		);
	}

	function fuzzyMatchRecursive(
		pattern,
		str,
		patternCurIndex,
		strCurrIndex,
		srcMatces,
		matches,
		maxMatches,
		nextMatch,
		recursionCount,
		recursionLimit
	) {
		let outScore = 0;

		// Return if recursion limit is reached.
		if (++recursionCount >= recursionLimit) {
			return [false, outScore];
		}

		// Return if we reached ends of strings.
		if (patternCurIndex === pattern.length || strCurrIndex === str.length) {
			return [false, outScore];
		}

		// Recursion params
		let recursiveMatch = false;
		let bestRecursiveMatches = [];
		let bestRecursiveScore = 0;

		// Loop through pattern and str looking for a match.
		let firstMatch = true;
		while (patternCurIndex < pattern.length && strCurrIndex < str.length) {
			// Match found.
			if (pattern[patternCurIndex].toLowerCase() === str[strCurrIndex].toLowerCase()) {
				if (nextMatch >= maxMatches) {
					return [false, outScore];
				}

				if (firstMatch && srcMatces) {
					matches = [...srcMatces];
					firstMatch = false;
				}

				const recursiveMatches = [];
				const [matched, recursiveScore] = fuzzyMatchRecursive(
					pattern,
					str,
					patternCurIndex,
					strCurrIndex + 1,
					matches,
					recursiveMatches,
					maxMatches,
					nextMatch,
					recursionCount,
					recursionLimit
				);

				if (matched) {
					// Pick best recursive score.
					if (!recursiveMatch || recursiveScore > bestRecursiveScore) {
						bestRecursiveMatches = [...recursiveMatches];
						bestRecursiveScore = recursiveScore;
					}
					recursiveMatch = true;
				}

				matches[nextMatch++] = strCurrIndex;
				++patternCurIndex;
			}
			++strCurrIndex;
		}

		const matched = patternCurIndex === pattern.length;

		if (matched) {
			outScore = 100;

			// Apply leading letter penalty
			let penalty = LEADING_LETTER_PENALTY * matches[0];
			penalty =
				penalty < MAX_LEADING_LETTER_PENALTY
					? MAX_LEADING_LETTER_PENALTY
					: penalty;
			outScore += penalty;

			//Apply unmatched penalty
			const unmatched = str.length - nextMatch;
			outScore += UNMATCHED_LETTER_PENALTY * unmatched;

			// Apply ordering bonuses
			for (let i = 0; i < nextMatch; i++) {
				const currIdx = matches[i];

				if (i > 0) {
					const prevIdx = matches[i - 1];
					if (currIdx == prevIdx + 1) {
						outScore += SEQUENTIAL_BONUS;
					}
				}

				// Check for bonuses based on neighbor character value.
				if (currIdx > 0) {
					// Camel case
					const neighbor = str[currIdx - 1];
					const curr = str[currIdx];
					if (
						neighbor !== neighbor.toUpperCase() &&
						curr !== curr.toLowerCase()
					) {
						outScore += CAMEL_BONUS;
					}
					const isNeighbourSeparator = neighbor == "_" || neighbor == " ";
					if (isNeighbourSeparator) {
						outScore += SEPARATOR_BONUS;
					}
				} else {
					// First letter
					outScore += FIRST_LETTER_BONUS;
				}
			}

			// Return best result
			if (recursiveMatch && (!matched || bestRecursiveScore > outScore)) {
				// Recursive score is better than "this"
				matches = [...bestRecursiveMatches];
				outScore = bestRecursiveScore;
				return [true, outScore];
			} else if (matched) {
				// "this" score is better than recursive
				return [true, outScore];
			} else {
				return [false, outScore];
			}
		}
		return [false, outScore];
	}


	if (odin_search.className == "odin-search-all" ||
	    odin_search.className == "odin-search-collection") {
		let entities = [];
		for (let [pkg_name, pkg] of Object.entries(odin_pkg_data.packages)) {
			for (let e of pkg.entities) {
				entities.push(e.full);
			}
		}

		entities.sort();
		// entities.sort(function (a, b) {
		// 	a = a.split(".", 2)[1];
		// 	b = b.split(".", 2)[1];
		// 	return a.localeCompare(b);
		// });

		let odin_search_results = document.getElementById("odin-search-results");

		let curr_search_value = "";
		odin_search.addEventListener("input", ev => {
			let search_text = odin_search.value.trim();
			if (curr_search_value != search_text) {
				curr_search_value = search_text;
				if (search_text) {
					let start_time = performance.now();

					let results_e_and_score = entities.map(e => [e, fuzzyMatch(search_text, e)]).filter(v => v[1][0]);

					results_e_and_score.sort(function (a, b) {
						return -(a[1] - b[1]);
					});

					let results = results_e_and_score.map(function(v) {
						return {"name": v[0], "score": v[1][1]}
					});
					results.sort(function(a, b) {
						return b.score - a.score;
					});

					let MAX_RESULTS_LENGTH = 64;

					if (results.length) {
						results.length = Math.min(results.length, MAX_RESULTS_LENGTH);
						let innerHTML = '';
						innerHTML = '';
						innerHTML += '<ul>\n';
						for (let result of results) {
							let parts = result.name.split(".", 2);
							let score = result.score;
							let pkg_name = parts[0], entity_name = parts[1];

							let pkg_path = odin_pkg_data.packages[pkg_name].path;

							innerHTML += `<li>${score}&mdash;<a href="${pkg_path}">${pkg_name}</a>.<a href="${pkg_path}/#${entity_name}">${entity_name}</a></li>\n`;
						}
						innerHTML += '</ul>';
						let end_time = performance.now();
						let diff = (end_time - start_time).toFixed(1);

						// innerHTML = `<p>Time to search ${diff} milliseconds</p>` + innerHTML

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
