"use strict";

var odin_pkg_name;

let odin_search = document.getElementById("odin-search");
if (odin_search) {
	function getElementsByClassNameArray(x) {
		return Array.from(document.getElementsByClassName(x));
	}

	function fuzzy_match(str, pattern) {

		// Score consts
		var adjacency_bonus = 5;                // bonus for adjacent matches
		var separator_bonus = 10;               // bonus if match occurs after a separator
		var camel_bonus = 10;                   // bonus if match is uppercase and prev is lower
		var leading_letter_penalty = -3;        // penalty applied for every letter in str before the first match
		var max_leading_letter_penalty = -9;    // maximum penalty for leading letters
		var unmatched_letter_penalty = -1;      // penalty for every letter that doesn't matter

		// Loop variables
		var score = 0;
		var patternIdx = 0;
		var patternLength = pattern.length;
		var strIdx = 0;
		var strLength = str.length;
		var prevMatched = false;
		var prevLower = false;
		var prevSeparator = true;       // true so if first letter match gets separator bonus

		// Use "best" matched letter if multiple string letters match the pattern
		var bestLetter = null;
		var bestLower = null;
		var bestLetterIdx = null;
		var bestLetterScore = 0;

		var matchedIndices = [];

		// Loop over strings
		while (strIdx != strLength) {
			var patternChar = patternIdx != patternLength ? pattern.charAt(patternIdx) : null;
			var strChar = str.charAt(strIdx);

			var patternLower = patternChar != null ? patternChar.toLowerCase() : null;
			var strLower = strChar.toLowerCase();
			var strUpper = strChar.toUpperCase();

			var nextMatch = patternChar && patternLower == strLower;
			var rematch = bestLetter && bestLower == strLower;

			var advanced = nextMatch && bestLetter;
			var patternRepeat = bestLetter && patternChar && bestLower == patternLower;
			if (advanced || patternRepeat) {
				score += bestLetterScore;
				matchedIndices.push(bestLetterIdx);
				bestLetter = null;
				bestLower = null;
				bestLetterIdx = null;
				bestLetterScore = 0;
			}

			if (nextMatch || rematch) {
				var newScore = 0;

				// Apply penalty for each letter before the first pattern match
				// Note: std::max because penalties are negative values. So max is smallest penalty.
				if (patternIdx == 0) {
					var penalty = Math.max(strIdx * leading_letter_penalty, max_leading_letter_penalty);
					score += penalty;
				}

				// Apply bonus for consecutive bonuses
				if (prevMatched)
					newScore += adjacency_bonus;

				// Apply bonus for matches after a separator
				if (prevSeparator)
					newScore += separator_bonus;

				// Apply bonus across camel case boundaries. Includes "clever" isLetter check.
				if (prevLower && strChar == strUpper && strLower != strUpper)
					newScore += camel_bonus;

				// Update patter index IFF the next pattern letter was matched
				if (nextMatch)
					++patternIdx;

				// Update best letter in str which may be for a "next" letter or a "rematch"
				if (newScore >= bestLetterScore) {

					// Apply penalty for now skipped letter
					if (bestLetter != null)
						score += unmatched_letter_penalty;

					bestLetter = strChar;
					bestLower = bestLetter.toLowerCase();
					bestLetterIdx = strIdx;
					bestLetterScore = newScore;
				}

				prevMatched = true;
			}
			else {
				// Append unmatch characters
				formattedStr += strChar;

				score += unmatched_letter_penalty;
				prevMatched = false;
			}

			// Includes "clever" isLetter check.
			prevLower = strChar == strLower && strLower != strUpper;
			prevSeparator = strChar == '_' || strChar == ' ';

			++strIdx;
		}

		// Apply score for last match
		if (bestLetter) {
			score += bestLetterScore;
			matchedIndices.push(bestLetterIdx);
		}

		// Finish out formatted string after last pattern matched
		// Build formated string based on matched letters
		var formattedStr = "";
		var lastIdx = 0;
		for (var i = 0; i < matchedIndices.length; ++i) {
			var idx = matchedIndices[i];
			formattedStr += str.substr(lastIdx, idx - lastIdx) + "<b>" + str.charAt(idx) + "</b>";
			lastIdx = idx + 1;
		}
		formattedStr += str.substr(lastIdx, str.length - lastIdx);

		var matched = patternIdx == patternLength;
		return [matched, score, formattedStr];
	}

	function fuzzy_entity_match(entities, search_text) {
		let results = [];
		for (let e of entities) {
			let [matched, score, formatted] = fuzzy_match(e, search_text);
			if (!matched) {
				continue;
			}

			if (e.includes(".")) {
				// Weight the name of the entity itself more than the entire thing
				let base_name = e.split(".", 2)[1];
				let [base_matched, base_score, _] = fuzzy_match(base_name, search_text);
				if (base_matched) {
					score += base_score;
				}
			}


			results.push({
				"name":      e,
				"score":     score,
				"formatted": formatted,
			});
		}

		results.sort(function(a, b) {
			return b.score - a.score;
		});

		return results;
	}


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
					let start_time = performance.now();

					let results = fuzzy_entity_match(entities, search_text);
					if (results.length) {
						let MAX_RESULTS_LENGTH = 64;
						results.length = Math.min(results.length, MAX_RESULTS_LENGTH);

						let innerHTML = '';
						innerHTML = '';
						innerHTML += '<ul>\n';
						for (let result of results) {
							let parts = result.name.split(".", 2);

							let score = result.score;
							let pkg_name = parts[0], entity_name = parts[1];

							let pkg_path = odin_pkg_data.packages[pkg_name].path;

							let formatted_parts = result.formatted.split(".", 2);
							innerHTML += `<li><a href="${pkg_path}/#${entity_name}"><a href="${pkg_path}">${formatted_parts[0]}</a>.<a href="${pkg_path}/#${entity_name}">${formatted_parts[1]}</a></a></li>\n`;
						}
						innerHTML += '</ul>';
						let end_time = performance.now();
						let diff = (end_time - start_time).toFixed(1);

						innerHTML = `<p>Time to search ${diff} milliseconds</p>` + innerHTML

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
					let results = fuzzy_entity_match(entities, search_text);
					if (results.length) {
						let result_names = results.map(e => e.name);

						setAllDisplays("none");
						for (let e of doc_entities) {
							let name = e.getElementsByTagName("h3")[0].id;
							let idx = result_names.indexOf(name);
							if (idx >= 0) {
								e.style.display = null;
								e.style.order = -results[idx].score;
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
			}
			ev.stopPropagation();
			return;
		}, false);
	}
}
