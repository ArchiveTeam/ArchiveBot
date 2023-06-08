"use strict";

function assert(condition, message) {
	if (!condition) {
		throw message || "Assertion failed";
	}
};

function byId(id) {
	return document.getElementById(id);
};

function text(s) {
	return document.createTextNode(s);
};

/**
 * Adaptation of ActiveSupport's #blank?.
 *
 * Returns true if the object is undefined, null, or is a string whose
 * post-trim length is zero.  Otherwise, returns false.
 */
function isBlank(o) {
	return !o || o.trim().length === 0;
}

/**
 * appendChild but accepts strings and arrays of children|strings
 */
function appendAny(e, thing) {
	if (Array.isArray(thing)) {
		for (const item of thing) {
			appendAny(e, item);
		}
	} else if (typeof thing == "string") {
		e.appendChild(text(thing));
	} else {
		if (thing == null) {
			throw Error("thing is " + JSON.stringify(thing));
		}
		e.appendChild(thing);
	}
};

/**
 * Create DOM element with attributes and children from Array<node|string>|node|string
 */
function h(elem, attrs, thing) {
	const e = document.createElement(elem);
	if (attrs != null) {
		for (let attr in attrs) {
			if (attr == "spellcheck" || attr == "readonly") {
				e.setAttribute(attr, attrs[attr]);
			} else if (attr == "class") {
				throw new Error("Did you mean className?");
			} else {
				e[attr] = attrs[attr];
			}
		}
	}
	if (thing != null) {
		appendAny(e, thing);
	}
	return e;
};

function href(href, text) {
	const a = h("a");
	a.href = href;
	a.textContent = text;
	return a;
};

function removeChildren(elem) {
	while (elem.firstChild) {
		elem.removeChild(elem.firstChild);
	}
};

function prettyJson(obj) {
	return JSON.stringify(obj, undefined, 2);
};

// Copied from Coreweb/js_coreweb/cw/string.js
/**
 * Like Python's s.split(delim, num) and s.split(delim)
 * This does *NOT* implement Python's no-argument s.split()
 *
 * @param {string} s The string to split.
 * @param {string} sep The separator to split by.
 * @param {number} maxsplit Maximum number of times to split.
 *
 * @return {!Array.<string>} The splitted string, as an array.
 */
function split(s, sep, maxsplit) {
	assert(typeof sep == "string",
		"arguments[1] of split must be a separator string");
	if (maxsplit === undefined || maxsplit < 0) {
		return s.split(sep);
	}
	const pieces = s.split(sep);
	const head = pieces.splice(0, maxsplit);
	// after the splice, pieces is shorter and no longer has the `head` elements.
	if (pieces.length > 0) {
		const tail = pieces.join(sep);
		head.push(tail); // no longer just the head.
	}
	return head;
};

// Based on closure-library's goog.string.regExpEscape
function regExpEscape(s) {
	let escaped = String(s).replace(/([-()\[\]{}+?*.$\^|,:#<!\\])/g, '\\$1').
		replace(/\x08/g, '\\x08');
	if (s.indexOf('[') == -1 && s.indexOf(']') == -1) {
		// If there were no character classes, there can't have been any need
		// to escape -, to unescape them.
		escaped = escaped.replace(/\\-/g, "-");
	}
	return escaped;
};

/**
 * [[1, 2], [3, 4]] -> {1: 2, 3: 4}
 */
function intoObject(arr) {
	const obj = {};
	arr.forEach(e => {
		obj[e[0]] = e[1];
	});
	return obj;
};

function getQueryArgs() {
	const pairs = location.search.replace("?", "").split("&");
	if (pairs == "") {
		return {};
	}
	return intoObject(pairs.map(e => split(e, "=", 1)));
};

function addAnyChangeListener(elem, func) {
	// DOM0 handler for convenient use by Clear button
	elem.onchange = func;
	elem.addEventListener('keydown', func, false);
	elem.addEventListener('paste', func, false);
	elem.addEventListener('input', func, false);
};

/**
 * Returns a function that gets the given property on any object passed in
 */
function prop(name) {
	return obj => obj[name];
};

/**
 * Returns a function that adds the given class to any element passed in
 */
function classAdder(name) {
	return elem => elem.classList.add(name);
};

/**
 * Returns a function that removes the given class to any element passed in
 */
function classRemover(name) {
	return elem => elem.classList.remove(name);
};

function removeFromArray(arr, item) {
	const idx = arr.indexOf(item);
	if (idx != -1) {
		arr.splice(idx, 1);
	}
};

/*** End of utility code ***/



class JobsTracker {
	constructor() {
		this.known = {};
		this.sorted = [];
		this.finishedArray = [];
		this.finishedSet = {};
		this.fatalExceptionSet = {};
	}

	countActive() {
		return this.sorted.length - this.finishedArray.length;
	}

	resort() {
		this.sorted.sort((a, b) =>
			a["started_at"] > b["started_at"] ? -1 : 1
		);
	}

	/**
	 * Returns true if a new job was added
	 */
	handleJobData(jobData) {
		const ident = jobData["ident"];
		const alreadyKnown = ident in this.known;
		if (!alreadyKnown) {
			this.known[ident] = true;
			this.sorted.push(jobData);
			this.resort();
		}
		return !alreadyKnown;
	};

	markFinished(ident) {
		if (!(ident in this.finishedSet)) {
			this.finishedSet[ident] = true;
			this.finishedArray.push(ident);
		}
	}

	markUnfinished(ident) {
		if (ident in this.finishedSet) {
			delete this.finishedSet[ident];
			removeFromArray(this.finishedArray, ident);
		}
		// Job was restarted, so unmark fatal exception
		if (ident in this.fatalExceptionSet) {
			delete this.fatalExceptionSet[ident];
		}
	}

	markFatalException(ident) {
		this.fatalExceptionSet[ident] = true;
	}

	hasFatalException(ident) {
		return ident in this.fatalExceptionSet;
	}
}



class JobRenderInfo {
	constructor(logWindow, logSegment, statsElements, jobNote, lineCountWindow, lineCountSegments) {
		this.logWindow = logWindow;
		this.logSegment = logSegment;
		this.statsElements = statsElements;
		this.jobNote = jobNote;
		this.lineCountWindow = lineCountWindow;
		this.lineCountSegments = lineCountSegments;
	}
}



const Reusable = {
	obj_className_line_normal: {"className": "line-normal"},
	obj_className_line_error: {"className": "line-error"},
	obj_className_line_warning: {"className": "line-warning"},
	obj_className_line_redirect: {"className": "line-redirect"},
	//
	obj_className_line_ignore: {"className": "line-ignore"},
	obj_className_line_stdout: {"className": "line-stdout"},
	obj_className_bold: {"className": "bold"}
};



// http://stackoverflow.com/questions/2901102/how-to-print-a-number-with-commas-as-thousands-separators-in-javascript
function numberWithCommas(s_or_n) {
	return ("" + s_or_n).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
};

function toStringTenths(n) {
	let s = "" + (Math.round(10 * n) / 10);
	if (s.indexOf(".") == -1) {
		s += ".0";
	}
	return s;
};

function getTotalResponses(jobData) {
	return (
		parseInt(jobData["r1xx"]) +
		parseInt(jobData["r2xx"]) +
		parseInt(jobData["r3xx"]) +
		parseInt(jobData["r4xx"]) +
		parseInt(jobData["r5xx"]) +
		parseInt(jobData["runk"]));
};

function getSummaryResponses(jobData) {
	return (
		"1xx: " + numberWithCommas(jobData["r1xx"]) + "\n" +
		"2xx: " + numberWithCommas(jobData["r2xx"]) + "\n" +
		"3xx: " + numberWithCommas(jobData["r3xx"]) + "\n" +
		"4xx: " + numberWithCommas(jobData["r4xx"]) + "\n" +
		"5xx: " + numberWithCommas(jobData["r5xx"]) + "\n" +
		"Unknown: " + numberWithCommas(jobData["runk"]));
};



class JobsRenderer {
	constructor(container, filterBox, historyLines, showNicks, contextMenuRenderer) {
		this.container = container;
		this.filterBox = filterBox;
		addAnyChangeListener(this.filterBox, () => this.applyFilter());
		this.filterBox.onkeypress = ev => {
			// So that j or k in input box does not result in job window switching
			ev.stopPropagation();
		};
		this.historyLines = historyLines;
		this.showNicks = showNicks;
		this.contextMenuRenderer = contextMenuRenderer;
		this.linesPerSegment = Math.max(1, Math.round(this.historyLines / 10));
		this.jobs = new JobsTracker();
		// ident -> JobRenderInfo
		this.renderInfo = {};
		this.mouseInside = null;
		this.numCrawls = byId('num-crawls');
		this.aligned = false;
	}

	_getNextJobInSorted(ident) {
		for (let i=0; i < this.jobs.sorted.length; i++) {
			const e = this.jobs.sorted[i];
			if (e["ident"] == ident) {
				return this.jobs.sorted[i+1];
			}
		}
		return null;
	}

	_createLogSegment() {
		return h('div');
	}

	_createLogContainer(jobData) {
		const ident = jobData["ident"];
		const beforeJob = this._getNextJobInSorted(ident);
		const beforeElement = beforeJob == null ? null : byId("log-container-" + beforeJob["ident"]);

		const logSegment = this._createLogSegment();

		const logWindowAttrs = {
			"className": "log-window",
			"id": "log-window-" + ident,
			"onmouseenter": ev => {
				this.mouseInside = ident;
				ev.target.classList.add('log-window-stopped');
			},
			"onmouseleave": ev => {
				const leave = () => {
					this.mouseInside = null;
					ev.target.classList.remove('log-window-stopped');
				};
				// When our custom context menu pops up, it causes onmouseleave on the
				// log window, so make our leave callback fire only after the context
				// menu is closed.
				if (this.contextMenuRenderer.visible) {
					this.contextMenuRenderer.callAfterBlur(leave);
				} else {
					leave();
				}
			}
		}

		const statsElements = {
			mb: h("span", {"className": "inline-stat job-mb"}, "?"),
			responses: h("span", {"className": "inline-stat job-responses"}, "?"),
			responsesPerSecond: h("span", {"className": "inline-stat job-responses-per-second"}, "?"),
			queueLength: h("span", {"className": "inline-stat job-in-queue"}, "? in q."),
			connections: h("span", {"className": "inline-stat job-connections"}, "?"),
			delay: h("span", {"className": "inline-stat job-delay"}, "? ms delay"),
			ignores: h("span", {"className": "job-ignores"}, "?"),
			jobInfo: null /* set later */
		};

		const startedISOString = new Date(parseFloat(jobData["started_at"]) * 1000).toISOString();
		const jobNote = h("span", {"className": "job-note"}, null);

		statsElements.jobInfo = h(
			"span", {"className": "job-info"}, [
				h("a", {"className": "inline-stat job-url", "href": jobData["url"]}, jobData["url"]),
				// Clicking anywhere in this area will set the filter to a regexp that
				// matches only this job URL, thus hiding everything but this job.
				h("span", {
					"className": "stats-elements",
					"onclick": () => {
						const filter = ds.getFilter();
						if (RegExp(filter).test(jobData["url"]) && filter.startsWith("^") && filter.endsWith("$")) {
							// If we're already showing just this log window, go back
							// to showing nothing.
							ds.setFilter("^$");
						} else {
							ds.setFilter("^" + regExpEscape(jobData["url"]) + "$");
						}
					}
				}, [
					" on ",
					h("span", {"className": "inline-stat", "title": startedISOString}, startedISOString.split("T")[0].substr(5)),
					h("span", {"className": "inline-stat job-nick"}, (this.showNicks ? " by " + jobData["started_by"] : "")),
					jobNote,
					"; ",
					statsElements.mb,
					" MB in ",
					statsElements.responses,
					" at ",
					statsElements.responsesPerSecond,
					"/s, ",
					statsElements.queueLength,
					"; ",
					statsElements.connections,
					" con. w/ ",
					statsElements.delay,
					"; ",
					statsElements.ignores
				])
			]
		);

		const logWindow = h('div', logWindowAttrs, logSegment);
		const div = h(
			'div',
			{"id": "log-container-" + ident}, [
				h("div", {"className": "job-header"}, [
					statsElements.jobInfo,
					h("input", {
						"className": "job-ident",
						"type": "text",
						"value": ident,
						"size": "28",
						"spellcheck": "false",
						"readonly": "",
						"onclick": () => this.select(),
					})
				]),
				logWindow
			]
		);
		this.renderInfo[ident] = new JobRenderInfo(logWindow, logSegment, statsElements, jobNote, 0, [0]);
		this.container.insertBefore(div, beforeElement);
		// Set appropriate CSS classes - we might be in aligned mode already
		this.updateAlign();
		// Filter hasn't changed, but we might need to filter out the new job, or
		// add/remove log-window-expanded class
		this.applyFilter();
	}

	_renderDownloadLine(data, logSegment) {
		let attrs;
		if (data["is_warning"]) {
			attrs = {"className": "line-warning", "href": data["url"]};
		} else if (data["is_error"]) {
			attrs = {"className": "line-error", "href": data["url"]};
		} else if (data["response_code"] && data["response_code"] >= 300 && data["response_code"] < 400) {
			attrs = {"className": "line-redirect", "href": data["url"]};
		} else {
			attrs = {"className": "line-normal", "href": data["url"]};
		}
		logSegment.appendChild(
			h("a", attrs, data["response_code"] + " " + data["wget_code"] + " " + data["url"])
		);
		return 1;
	}

	/**
	 * Like _renderDownloadLine, but makes it easier to start a text selection from the
	 * left or right of the URL.
	 */
	_moreDomRenderDownloadLine(data, logSegment) {
		let attrs;
		if (data["is_warning"]) {
			attrs = Reusable.obj_className_line_warning;
		} else if (data["is_error"]) {
			attrs = Reusable.obj_className_line_error;
		} else if (data["response_code"] && data["response_code"] >= 300 && data["response_code"] < 400) {
			attrs = Reusable.obj_className_line_redirect;
		} else {
			attrs = Reusable.obj_className_line_normal;
		}
		logSegment.appendChild(h("div", attrs, [
			data["response_code"] + " " + data["wget_code"] + " ",
			h("a", {"href": data["url"], "className": "log-url"}, data["url"])
		]));
		return 1;
	}

	_renderIgnoreLine(data, logSegment) {
		const attrs = Reusable.obj_className_line_ignore;
		const source = data["source"];
		let ignoreSpan;

		if (source != null) {
			ignoreSpan = h('span', null, " IGNOR (" + source + "): ");
		} else {
			ignoreSpan = h('span', null, " IGNOR ");
		}

		logSegment.appendChild(h("div", attrs, [
			ignoreSpan,
			h('a', {"href": data["url"], "className": "ignore"}, data["url"]),
			h('span', Reusable.obj_className_bold, " by "),
			data["pattern"]
		]));
		return 1;
	}

	_renderStdoutLine(data, logSegment, info, ident) {
		const cleanedMessage = data["message"].replace(/[\r\n]+$/, "");
		let renderedLines = 0;
		if (!cleanedMessage) {
			return renderedLines;
		}
		const lines = cleanedMessage.split("\n");
		for (const line of lines) {
			if (!line) {
				continue;
			}
			logSegment.appendChild(h("div", Reusable.obj_className_line_stdout, line));
			renderedLines += 1;

			// Check for 'Finished RsyncUpload for Item'
			// instead of 'Starting MarkItemAsDone for Item'
			// because the latter is often missing
			if (/^Finished RsyncUpload for Item/.test(line)) {
				info.statsElements.jobInfo.classList.add('job-info-done');
				this.jobs.markFinished(ident);
			} else if (/^CRITICAL (Sorry|Please report)|^ERROR Fatal exception|No space left on device|^Fatal Python error:|^(Thread|Current thread) 0x/.test(line)) {
				info.statsElements.jobInfo.classList.add('job-info-fatal');
				this.jobs.markFatalException(ident);
			} else if (/Script requested immediate stop|^Adjusted target WARC path to.*-aborted$/.test(line)) {
				// Note: above message can be in:
				// ERROR Script requested immediate stop
				// or after an ERROR Fatal exception:
				// wpull.hook.HookStop: Script requested immediate stop.
				//
				// Also check for "Adjusted target WARC path" because
				// the exception may be entirely missing.
				info.statsElements.jobInfo.classList.remove('job-info-fatal');
				info.statsElements.jobInfo.classList.add('job-info-aborted');
			} else if (/^Received item /.test(line)) {
				// Clear other statuses if a job restarts with the same job ID
				info.statsElements.jobInfo.classList.remove('job-info-done');
				info.statsElements.jobInfo.classList.remove('job-info-fatal');
				info.statsElements.jobInfo.classList.remove('job-info-aborted');
				this.jobs.markUnfinished(ident);
			}
		}
		return renderedLines;
	}

	handleData(data) {
		const jobData = data["job_data"];
		const added = this.jobs.handleJobData(jobData);
		this.numCrawls.textContent = this.jobs.countActive();
		if (added) {
			this._createLogContainer(jobData);
		}
		const type = data["type"];
		const ident = jobData["ident"];

		const info = this.renderInfo[ident];
		if (!info) {
			console.warn("No render info for " + ident);
			return;
		}

		const totalResponses = parseInt(getTotalResponses(jobData));
		let linesRendered;
		if (type == "download") {
			linesRendered = this._renderDownloadLine(data, info.logSegment);
		} else if (type == "stdout") {
			linesRendered = this._renderStdoutLine(data, info.logSegment, info, ident);
		} else if (type == "ignore") {
			linesRendered = this._renderIgnoreLine(data, info.logSegment);
		} else {
			assert(false, "Unexpected message type " + type);
		}

		// Update stats
		info.statsElements.mb.textContent =
			numberWithCommas(
				toStringTenths(
					(parseInt(jobData["bytes_downloaded"]) / (1024 * 1024)).toString()));
		info.statsElements.responses.textContent =
			numberWithCommas(totalResponses) + " resp.";
		info.statsElements.responses.title = getSummaryResponses(jobData);
		const duration = Date.now()/1000 - parseFloat(jobData["started_at"]);
		info.statsElements.responsesPerSecond.textContent =
			toStringTenths(totalResponses/duration);

		if (jobData["items_queued"] && jobData["items_downloaded"]) {
			const totalQueued = parseInt(jobData["items_queued"], 10);
			const totalDownloaded = parseInt(jobData["items_downloaded"], 10);
			info.statsElements.queueLength.textContent =
				numberWithCommas((totalQueued - totalDownloaded) + " in q.");
			info.statsElements.queueLength.title =
				numberWithCommas(totalQueued) + " queued\n" +
				numberWithCommas(totalDownloaded) + " downloaded";
		}

		info.statsElements.connections.textContent = jobData["concurrency"];

		const delayMin = parseInt(jobData["delay_min"]);
		const delayMax = parseInt(jobData["delay_max"]);
		info.statsElements.delay.textContent =
			(delayMin == delayMax ?
				delayMin :
				delayMin + "-" + delayMax) + " ms delay";

		if (jobData["suppress_ignore_reports"]) {
			info.statsElements.ignores.textContent = 'igoff';
			if (!info.statsElements.ignores.classList.contains('job-igoff')) {
				info.statsElements.ignores.classList.add('job-igoff');
			}
		} else {
			info.statsElements.ignores.textContent = 'igon';
			if (info.statsElements.ignores.classList.contains('job-igoff')) {
				info.statsElements.ignores.classList.remove('job-igoff');
			}
		}

		// Update note
		info.jobNote.textContent =
			isBlank(jobData["note"]) ?
				"" :
				" (" + jobData["note"] + ")";

		info.lineCountWindow += linesRendered;
		info.lineCountSegments[info.lineCountSegments.length - 1] += linesRendered;

		if (info.lineCountSegments[info.lineCountSegments.length - 1] >= this.linesPerSegment) {
			//console.log("Created new segment", info);
			const newSegment = this._createLogSegment();
			info.logWindow.appendChild(newSegment);
			info.logSegment = newSegment;
			info.lineCountSegments.push(0);
		}

		if (this.mouseInside != ident) {
			// Don't remove any scrollback information when the job has a fatal exception,
			// so that the user can find the traceback and report a bug.
			if (!this.jobs.hasFatalException(ident)) {
				// We may have to remove more than one segment, if the user
				// has paused the log window for a while.
				while (info.lineCountWindow >= this.historyLines + this.linesPerSegment) {
					const firstLogSegment = info.logWindow.firstChild;
					assert(firstLogSegment != null, "info.logWindow.firstChild is null; " +
						JSON.stringify({
							"lineCountWindow": info.lineCountWindow,
							"lineCountSegments": info.lineCountSegments}));
					info.logWindow.removeChild(firstLogSegment);
					info.lineCountWindow -= info.lineCountSegments[0];
					info.lineCountSegments.shift();
				}
			}

			// Scroll to the bottom
			// To avoid serious performance problems in Firefox, we use a big number
			// instead of info.logWindow.scrollHeight.
			info.logWindow.scrollTop = 999999;
		}
	}

	applyFilter() {
		const query = this.filterBox.value;
		let matches = 0;
		const matchedWindows = [];
		const unmatchedWindows = [];
		this.firstFilterMatch = null;
		for (const job of this.jobs.sorted) {
			const w = this.renderInfo[job["ident"]].logWindow;
			if (!RegExp(query).test(job["url"])) {
				w.classList.add("log-window-hidden");

				unmatchedWindows.push(w);
			} else {
				w.classList.remove("log-window-hidden");

				matches += 1;
				matchedWindows.push(w);
				if (this.firstFilterMatch == null) {
					this.firstFilterMatch = job;
				}
			}
		}

		// If there's only one visible log window, expand it so that more lines are visible.
		unmatchedWindows.map(classRemover('log-window-expanded'));
		matchedWindows.map(classRemover('log-window-expanded'));
		if (matches == 1) {
			matchedWindows.map(classAdder('log-window-expanded'));
		}

		if (matches < this.jobs.sorted.length) {
			// If you're not seeing all of the log windows, you're probably seeing very
			// few of them, so you probably want alignment enabled.
			this.aligned = true;
			this.updateAlign();
		} else {
			// You're seeing all of the log windows, so alignment doesn't help as much
			// as seeing the full info.
			this.aligned = false;
			this.updateAlign();
		}
	}

	showNextPrev(offset) {
		let idx;
		if (this.firstFilterMatch == null) {
			idx = null;
		} else {
			idx = this.jobs.sorted.findIndex(el => {
				return el["ident"] === this.firstFilterMatch["ident"];
			});
		}
		if (idx == null) {
			// If no job windows are shown, set up index to make j show the first job window,
			// k the last job window.
			idx = this.jobs.sorted.length;
		}
		idx = idx + offset;
		// When reaching either end, hide all job windows.  When going past
		// the end, wrap around.
		if (idx == -1) {
			idx = this.jobs.sorted.length;
		} else if (idx == this.jobs.sorted.length + 1) {
			idx = 0;
		}
		if (idx == this.jobs.sorted.length) {
			ds.setFilter("^$");
		} else {
			const newShownJob = this.jobs.sorted[idx];
			ds.setFilter("^" + regExpEscape(newShownJob["url"]) + "$");
		}
	}

	updateAlign() {
		const adderOrRemover = this.aligned ? classAdder : classRemover;
		Array.from(document.querySelectorAll('.job-url')).map(adderOrRemover('job-url-aligned'));
		Array.from(document.querySelectorAll('.job-note')).map(adderOrRemover('job-note-aligned'));
		Array.from(document.querySelectorAll('.job-nick')).map(adderOrRemover('job-nick-aligned'));
		Array.from(document.querySelectorAll('.job-mb')).map(adderOrRemover('job-mb-aligned'));
		Array.from(document.querySelectorAll('.job-responses')).map(adderOrRemover('job-responses-aligned'));
		Array.from(document.querySelectorAll('.job-responses-per-second')).map(adderOrRemover('job-responses-per-second-aligned'));
		Array.from(document.querySelectorAll('.job-in-queue')).map(adderOrRemover('job-in-queue-aligned'));
		Array.from(document.querySelectorAll('.job-connections')).map(adderOrRemover('job-connections-aligned'));
		Array.from(document.querySelectorAll('.job-delay')).map(adderOrRemover('job-delay-aligned'));
	}

	toggleAlign() {
		this.aligned = !this.aligned;
		this.updateAlign();
	}
}



/**
 * This context menu pops up when you right-click on a URL in
 * a log window, helping you copy an !ig command based on the URL
 * you right-clicked.
 */
class ContextMenuRenderer {
	constructor() {
		this.visible = false;
		this.callAfterBlurFns = [];
		this.element = byId('context-menu');
	}

	/**
	 * Returns true if the event target is a URL in a log window
	 */
	clickedOnLogWindowURL(ev) {
		const cn = ev.target.className;
		return cn == "line-normal" || cn == "line-error" || cn == "line-warning" || cn == "line-redirect" || cn == "log-url";
	}

	makeCopyTextFn(text) {
		return () => {
			const clipboardScratchpad = byId('clipboard-scratchpad');
			clipboardScratchpad.value = text;
			clipboardScratchpad.focus();
			clipboardScratchpad.select();
			document.execCommand('copy');
		};
	}

	getPathVariants(path) {
		const paths = [path];

		// Avoid generating a duplicate suggestion
		path = path.replace(/\/$/, "");

		while (path && path.lastIndexOf('/') != -1) {
			path = path.replace(/\/[^\/]*$/, "");
			paths.push(path + '/');
		}

		return paths;
	}

	getSuggestedCommands(ident, url) {
		const schema = url.split(':')[0];
		const domain = url.split('/')[2];
		const withoutQuery = url.split('?')[0];
		const path = '/' + split(withoutQuery, '/', 3)[3];
		const reSchema = schema.startsWith('http') ? 'https?' : 'ftp';
		return this.getPathVariants(path).map(p => {
			return "!ig " + ident + " ^" + reSchema + "://" + regExpEscape(domain + p);
		}).concat([
			"!d " + ident + " 180000 180000",
			"!d " + ident + " 250 375",
			"!con " + ident + " 1",
		]);
	}

	makeEntries(ident, url) {
		const commands = this.getSuggestedCommands(ident, url).map(c => {
			return h(
				'span',
				{'onclick': this.makeCopyTextFn(c)},
				"Copy " + c.replace(" " + ident + " ", " … ")
			);
		});
		return [
			// Unfortunately, this does not open it in a background tab
			// like the real context menu does.
			h('a', {'href': url}, "Open link in new tab")
			,h('span', {'onclick': this.makeCopyTextFn(url)}, "Copy link address")
		].concat(commands);
	}

	onContextMenu(ev) {
		//console.log(ev);
		if (!this.clickedOnLogWindowURL(ev)) {
			this.blur();
			return;
		}
		ev.preventDefault();
		this.visible = true;
		this.element.style.display = "block";
		this.element.style.left = ev.clientX + "px";
		this.element.style.top = ev.clientY + "px";

		removeChildren(this.element);
		// We put the clipboard-scratchpad in the fixed-positioned
		// context menu instead of elsewhere on the page, because
		// we must focus the input box to automatically copy its text,
		// and the focus operation scrolls to the element on the page,
		// and we want to avoid such scrolling.
		appendAny(this.element, h('input', {'type': 'text', 'id': 'clipboard-scratchpad'}));

		const url = ev.target.href;
		let ident;
		try {
			ident = ev.target.parentNode.parentNode.id.match(/^log-window-(.*)/)[1];
		} catch(e) {
			// moreDom=1
			ident = ev.target.parentNode.parentNode.parentNode.id.match(/^log-window-(.*)/)[1];
		}
		const entries = this.makeEntries(ident, url);
		for (const entry of entries) {
			entry.classList.add('context-menu-entry');
			appendAny(this.element, entry);
		}

		// If the bottom of the context menu is outside the viewport, move the context
		// menu up, so that it appears to have opened from its bottom-left corner.
		// + 1 pixel so that the pointer lands inside the element and turns on cursor: default
		if (ev.clientY + this.element.offsetHeight > document.documentElement.clientHeight) {
			this.element.style.top = (ev.clientY - this.element.offsetHeight + 1) + "px";
		}
	}

	blur() {
		this.visible = false;
		this.element.style.display = "none";
		this.callAfterBlurFns.map(fn => fn());
		this.callAfterBlurFns = [];
	}

	// TODO: decouple - fire an onblur event instead
	callAfterBlur(fn) {
		this.callAfterBlurFns.push(fn);
	}
}



class BatchingQueue {
	constructor(callable, minInterval) {
		this.callable = callable;
		this._minInterval = minInterval;
		this.queue = [];
		this._timeout = null;
	}

	setMinInterval(minInterval) {
		this._minInterval = minInterval;
	}

	_runCallable() {
		this._timeout = null;
		const queue = this.queue;
		this.queue = [];
		this.callable(queue);
	}

	callNow() {
		if (this._timeout !== null) {
			clearTimeout(this._timeout);
			this._timeout = null;
		}
		this._runCallable();
	}

	push(v) {
		this.queue.push(v);
		if (this._timeout === null) {
			this._timeout = setTimeout(() => this._runCallable(), this._minInterval);
		}
	}
};



class Decayer {
	constructor(initial, multiplier, max) {
		this.initial = initial;
		this.multiplier = multiplier;
		this.max = max;
		this.reset();
	}

	reset() {
		// First call to .decay() will multiply, but we want to get the `intitial`
		// value on the first call to .decay(), so divide.
		this.current = this.initial / this.multiplier;
		return this.current;
	}

	decay() {
		this.current = Math.min(this.current * this.multiplier, this.max);
		return this.current;
	}
};



class Dashboard {
	constructor() {
		this.messageCount = 0;

		const args = getQueryArgs();

		const historyLines         = args["historyLines"]         ? Number(args["historyLines"])         : navigator.userAgent.match(/Mobi/) ? 250 : 500;
		const batchTimeWhenVisible = args["batchTimeWhenVisible"] ? Number(args["batchTimeWhenVisible"]) : 125;
		const showNicks            = args["showNicks"]            ? Boolean(Number(args["showNicks"]))   : false;
		const contextMenu          = args["contextMenu"]          ? Boolean(Number(args["contextMenu"])) : true;
		const moreDom              = args["moreDom"]              ? Boolean(Number(args["moreDom"]))     : false;
		// Append to page title to make it possible to identify the tab in Chrome's task manager
		if (args["title"]) {
			document.title += " - " + args["title"];
		}

		if (moreDom) {
			JobsRenderer.prototype._renderDownloadLine = JobsRenderer.prototype._moreDomRenderDownloadLine;
		}

		this.host = args["host"] ? args["host"] : location.hostname;
		this.dumpTraffic = args["dumpMax"] && Number(args["dumpMax"]) > 0;
		if (this.dumpTraffic) {
			this.dumpMax = Number(args["dumpMax"]);
		}

		this.contextMenuRenderer = new ContextMenuRenderer(document);
		if (contextMenu) {
			document.oncontextmenu = ev => this.contextMenuRenderer.onContextMenu(ev);
			document.onclick = ev => this.contextMenuRenderer.blur(ev);
			// onkeydown picks up ESC, onkeypress doesn't (tested Chrome 44)
			document.onkeydown = ev => {
				if (ev.keyCode == 27) { // ESC
					this.contextMenuRenderer.blur();
				}
			};
			document.onwheel = () => this.contextMenuRenderer.blur();
		}

		this.jobsRenderer = new JobsRenderer(
			byId('logs'), byId('filter-box'), historyLines, showNicks, this.contextMenuRenderer);

		const batchTimeWhenHidden = 1000;

		const xhr = new XMLHttpRequest();

		const finishSetup = () => {
			this.queue = new BatchingQueue(queue => {
				//console.log("Queue has ", queue.length, "items");
				for (const item of queue) {
					this.handleData(JSON.parse(item));
				}
			}, batchTimeWhenVisible);

			this.decayer = new Decayer(1000, 1.5, 60000);
			this.connectWebSocket();

			document.addEventListener("visibilitychange", () => {
				if (document.hidden) {
					//console.log("Page has become hidden");
					this.queue.setMinInterval(batchTimeWhenHidden);
				} else {
					//console.log("Page has become visible");
					this.queue.setMinInterval(batchTimeWhenVisible);
					this.queue.callNow();
				}
			}, false);
		};

		xhr.onload = () => {
			try {
				const recentLines = JSON.parse(xhr.responseText);
				for (const line of recentLines) {
					this.handleData(line);
				}
			} catch(e) {
				console.log("Failed to load /logs/recent data:", e);
			}
			finishSetup();
		};
		xhr.onerror = () => {
			// Try to continue despite lack of /logs/recent data
			finishSetup();
		};
		xhr.open("GET", "/logs/recent?cb=" + Date.now() + Math.random());
		xhr.setRequestHeader('Accept', 'application/json');
		xhr.send("");

		document.onkeypress = ev => this.keyPress(ev);

		// Adjust help text based on URL
		Array.prototype.slice.call(document.querySelectorAll('.url-q-or-amp')).map(elem => {
			if (window.location.search.indexOf("?") != -1) {
				elem.textContent = "&";
			}
		});

		if (!showNicks) {
			document.write('<style>.job-nick-aligned { width: 0; }</style>');
		}
	}

	keyPress(ev) {
		//console.log(ev);

		// If you press ctrl-f or alt-f in Firefox (tested: 41), it dispatches
		// the keypress event for 'f'.  We want only the modifier-free
		// keypresses.
		if (ev.ctrlKey || ev.altKey || ev.metaKey) {
			return;
		}
		// Check shiftKey only after handling '?', because you need shift for '?'
		if (ev.which == 63) { // ?
			ds.toggleHelp();
			return;
		}
		if (ev.shiftKey) {
			return;
		}
		if (ev.which == 106) { // j
			this.jobsRenderer.showNextPrev(1);
		} else if (ev.which == 107) { // k
			this.jobsRenderer.showNextPrev(-1);
		} else if (ev.which == 97) { // a
			ds.setFilter('');
		} else if (ev.which == 110) { // n
			ds.setFilter('^$');
		} else if (ev.which == 102) { // f
			ev.preventDefault();
			byId('filter-box').focus();
			byId('filter-box').select();
		} else if (ev.which == 118) { // v
			window.open(this.jobsRenderer.firstFilterMatch["url"]);
		}
	}

	handleData(data) {
		this.messageCount += 1;
		if (this.dumpTraffic && this.messageCount <= this.dumpMax) {
			byId('traffic').appendChild(h("pre", null, prettyJson(data)));
		}
		this.jobsRenderer.handleData(data);
	}

	connectWebSocket() {
		const wsproto = window.location.protocol === "https:" ? "wss:" : "ws:";

		this.ws = new WebSocket(wsproto + "//" + this.host + ":4568/stream");

		this.ws.onmessage = ev => {
			this.queue.push(ev["data"]);
		};

		this.ws.onopen = ev => {
			console.log("WebSocket opened:", ev);
			this.decayer.reset();
		};

		this.ws.onclose = ev => {
			console.log("WebSocket closed:", ev);
			const delay = this.decayer.decay();
			console.log("Reconnecting in", delay, "ms");
			setTimeout(() => this.connectWebSocket(), delay);
		};
	}

	toggleAlign() {
		this.jobsRenderer.toggleAlign();
	}

	toggleHelp() {
		const help = byId('help');
		if (help.classList.contains('undisplayed')) {
			help.classList.remove('undisplayed');
		} else {
			help.classList.add('undisplayed');
		}
	}

	getFilter(value) {
		return byId('filter-box').value;
	}

	setFilter(value) {
		byId('filter-box').value = value;
		byId('filter-box').onchange();
	}
}

const ds = new Dashboard();
