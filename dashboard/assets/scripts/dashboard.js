/**
 * This file should be formatted with
 * rome check dashboard/assets/scripts/dashboard.js --apply-unsafe --line-width 120
 */

"use strict";

function assert(condition, message) {
	if (!condition) {
		throw message || "Assertion failed";
	}
}

function byId(id) {
	return document.getElementById(id);
}

function text(s) {
	return document.createTextNode(s);
}

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
	} else if (typeof thing === "string") {
		e.appendChild(text(thing));
	} else {
		if (thing == null) {
			throw Error(`thing is ${JSON.stringify(thing)}`);
		}
		e.appendChild(thing);
	}
}

/**
 * Create DOM element with attributes and children from Array<node|string>|node|string
 */
function h(elem, attrs, thing) {
	const e = document.createElement(elem);
	if (attrs != null) {
		for (const attr in attrs) {
			if (attr === "spellcheck" || attr === "readonly") {
				e.setAttribute(attr, attrs[attr]);
			} else if (attr === "class") {
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
}

function removeChildren(elem) {
	while (elem.firstChild) {
		elem.removeChild(elem.firstChild);
	}
}

function addPageStyles(cssText) {
	const style = document.createElement("style");
	style.innerHTML = cssText;
	document.body.appendChild(style);
}

function prettyJson(obj) {
	return JSON.stringify(obj, undefined, 2);
}

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
	assert(typeof sep === "string", "arguments[1] of split must be a separator string");
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
}

// Based on closure-library's goog.string.regExpEscape
function regExpEscape(s) {
	let escaped = String(s).replace(/([-()\[\]{}+?*.$\^|,:#<!\\])/g, "\\$1").replace(/\x08/g, "\\x08");
	if (s.indexOf("[") === -1 && s.indexOf("]") === -1) {
		// If there were no character classes, there can't have been any need
		// to escape -, to unescape them.
		escaped = escaped.replace(/\\-/g, "-");
	}
	return escaped;
}

function addAnyChangeListener(elem, func) {
	// DOM0 handler for convenient use by Clear button
	elem.onchange = func;
	elem.addEventListener("keydown", func, false);
	elem.addEventListener("paste", func, false);
	elem.addEventListener("input", func, false);
}

function scrollToBottom(elem) {
	// Scroll to the bottom. To avoid serious performance problems in Firefox,
	// use a big number instead of elem.scrollHeight.
	elem.scrollTop = 999999;
}

/**
 * Returns a function that gets the given property on any object passed in
 */
function prop(name) {
	return (obj) => obj[name];
}

/**
 * Returns a function that adds the given class to any element passed in
 */
function classAdder(name) {
	return (elem) => elem.classList.add(name);
}

/**
 * Returns a function that removes the given class to any element passed in
 */
function classRemover(name) {
	return (elem) => elem.classList.remove(name);
}

function removeFromArray(arr, item) {
	const idx = arr.indexOf(item);
	if (idx !== -1) {
		arr.splice(idx, 1);
	}
}

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
		this.sorted.sort((a, b) => (a.started_at > b.started_at ? -1 : 1));
	}

	/**
	 * Returns true if a new job was added
	 */
	handleJobData(jobData) {
		const ident = jobData.ident;
		const alreadyKnown = ident in this.known;
		if (!alreadyKnown) {
			this.known[ident] = true;
			this.sorted.push(jobData);
			this.resort();
		}
		return !alreadyKnown;
	}

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
	constructor(logWindow, logSegment, statsElements, jobUrl, jobNote, lineCountWindow, lineCountSegments) {
		this.logWindow = logWindow;
		this.logSegment = logSegment;
		this.statsElements = statsElements;
		this.jobUrl = jobUrl;
		this.jobNote = jobNote;
		this.lineCountWindow = lineCountWindow;
		this.lineCountSegments = lineCountSegments;
	}
}

const Reusable = {
	obj_className_line_normal: { className: "line-normal" },
	obj_className_line_error: { className: "line-error" },
	obj_className_line_warning: { className: "line-warning" },
	obj_className_line_redirect: { className: "line-redirect" },
	//
	obj_className_line_ignore: { className: "line-ignore" },
	obj_className_line_stdout: { className: "line-stdout" },
	obj_className_bold: { className: "bold" },
};

// http://stackoverflow.com/questions/2901102/how-to-print-a-number-with-commas-as-thousands-separators-in-javascript
function numberWithCommas(s_or_n) {
	return `${s_or_n}`.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

function toStringTenths(n) {
	let s = `${Math.round(10 * n) / 10}`;
	if (s !== "NaN" && s.indexOf(".") === -1) {
		s += ".0";
	}
	return s;
}

function getTotalResponses(jobData) {
	return (
		parseInt(jobData.r1xx) +
		parseInt(jobData.r2xx) +
		parseInt(jobData.r3xx) +
		parseInt(jobData.r4xx) +
		parseInt(jobData.r5xx) +
		parseInt(jobData.runk)
	);
}

function getSummaryResponses(jobData) {
	return `1xx: ${numberWithCommas(jobData.r1xx)}
2xx: ${numberWithCommas(jobData.r2xx)}
3xx: ${numberWithCommas(jobData.r3xx)}
4xx: ${numberWithCommas(jobData.r4xx)}
5xx: ${numberWithCommas(jobData.r5xx)}
Unknown: ${numberWithCommas(jobData.runk)}`;
}

class JobsRenderer {
	constructor(container, filterBox, historyLines, showNicks, contextMenuRenderer) {
		this.container = container;
		this.filterBox = filterBox;
		addAnyChangeListener(this.filterBox, () => this.applyFilter());
		this.filterBox.onkeypress = (ev) => {
			// Don't let `j` or `k` in the filter box cause the job window to switch
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
		this.numCrawls = byId("num-crawls");
		this._aligned = true;
	}

	_getNextJobInSorted(ident) {
		for (let i = 0; i < this.jobs.sorted.length; i++) {
			const e = this.jobs.sorted[i];
			if (e.ident === ident) {
				return this.jobs.sorted[i + 1];
			}
		}
		return null;
	}

	_createLogSegment() {
		return h("div");
	}

	_createLogContainer(jobData) {
		const ident = jobData.ident;
		const beforeJob = this._getNextJobInSorted(ident);
		const beforeElement = beforeJob == null ? null : byId(`log-container-${beforeJob.ident}`);

		const logSegment = this._createLogSegment();

		const logWindowAttrs = {
			className: "log-window",
			id: `log-window-${ident}`,
			onmouseenter: (ev) => {
				this.mouseInside = ident;
				ev.target.classList.add("log-window-stopped");
			},
			onmouseleave: (ev) => {
				const leave = () => {
					this.mouseInside = null;
					ev.target.classList.remove("log-window-stopped");
				};
				// When our custom context menu pops up, it causes onmouseleave on the
				// log window, so make our leave callback fire only after the context
				// menu is closed.
				if (this.contextMenuRenderer.visible) {
					this.contextMenuRenderer.callAfterBlur(leave);
				} else {
					leave();
				}
			},
		};

		const maybeAligned = (className) => {
			let s = className;
			if (this._aligned) {
				s += ` ${className}-aligned`;
			}
			return s;
		};

		const statsElements = {
			mb: h("span", { className: `inline-stat ${maybeAligned("job-mb")}` }, "?"),
			responses: h("span", { className: `inline-stat ${maybeAligned("job-responses")}` }, "?"),
			responsesPerSecond: h("span", { className: `inline-stat ${maybeAligned("job-responses-per-second")}` }, "?"),
			queueLength: h("span", { className: `inline-stat ${maybeAligned("job-in-queue")}` }, "? in q."),
			connections: h("span", { className: `inline-stat ${maybeAligned("job-connections")}` }, "?"),
			delay: h("span", { className: `inline-stat ${maybeAligned("job-delay")}` }, "? ms delay"),
			ignores: h("span", { className: "job-ignores" }, "?"),
			jobInfo: null /* set later */,
		};

		const startedISOString = new Date(parseFloat(jobData.started_at) * 1000).toISOString();
		const jobNote = h("span", { className: maybeAligned("job-note") }, null);

		statsElements.jobInfo = h("span", { className: "job-info" }, [
			h("a", { className: `inline-stat ${maybeAligned("job-url")}`, href: jobData.url }, jobData.url),
			// Clicking anywhere in this area will set the filter to a regexp that
			// matches only this job URL, thus hiding everything but this job.
			h(
				"span",
				{
					className: "stats-elements",
					onclick: () => {
						const filter = ds.getFilter();
						if (RegExp(filter).test(jobData.url) && filter.startsWith("^") && filter.endsWith("$")) {
							// If we're already showing just this log window, go back
							// to showing nothing.
							ds.setFilter("^$");
						} else {
							ds.setFilter(`^${regExpEscape(jobData.url)}$`);
						}
					},
				},
				[
					" on ",
					h("span", { className: "inline-stat", title: startedISOString }, startedISOString.split("T")[0].substr(5)),
					h(
						"span",
						{ className: `inline-stat ${maybeAligned("job-nick")}` },
						this.showNicks ? ` by ${jobData.started_by}` : "",
					),
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
					statsElements.ignores,
				],
			),
		]);
		const jobUrl = statsElements.jobInfo.querySelector(".job-url");

		const logWindow = h("div", logWindowAttrs, logSegment);
		const div = h("div", { className: "log-container", id: `log-container-${ident}` }, [
			h("div", { className: "job-header" }, [statsElements.jobInfo, h("span", { className: "job-ident" }, ident)]),
			logWindow,
		]);
		this.renderInfo[ident] = new JobRenderInfo(logWindow, logSegment, statsElements, jobUrl, jobNote, 0, [0]);
		this.container.insertBefore(div, beforeElement);
		// Filter hasn't changed, but we might need to filter out the new job, or
		// add/remove log-window-expanded class
		this.applyFilter();
	}

	_renderDownloadLine(data, logSegment) {
		let attrs;
		if (data.is_warning) {
			attrs = Reusable.obj_className_line_warning;
		} else if (data.is_error) {
			attrs = Reusable.obj_className_line_error;
		} else if (data.response_code && data.response_code >= 300 && data.response_code < 400) {
			attrs = Reusable.obj_className_line_redirect;
		} else {
			attrs = Reusable.obj_className_line_normal;
		}
		const url = data.url;
		// For testing a URL with characters that browsers like to escape, breaking the suggested ignores
		// url = "http://example.com/m/index.php/{$ibforums-%3Evars[TEAM_ICON_URL]}/t82380.html^hi";
		logSegment.appendChild(
			h("div", attrs, [`${data.response_code} ${data.wget_code} `, h("a", { href: url, className: "log-url" }, url)]),
		);
		return 1;
	}

	_renderIgnoreLine(data, logSegment) {
		const attrs = Reusable.obj_className_line_ignore;
		const source = data.source;
		let ignoreSpan;

		if (source != null) {
			ignoreSpan = h("span", null, ` IGNOR (${source}): `);
		} else {
			ignoreSpan = h("span", null, " IGNOR ");
		}

		logSegment.appendChild(
			h("div", attrs, [
				ignoreSpan,
				h("a", { href: data.url, className: "ignore" }, data.url),
				h("span", Reusable.obj_className_bold, " by "),
				data.pattern,
			]),
		);
		return 1;
	}

	_renderStdoutLine(data, logSegment, info, ident) {
		const cleanedMessage = data.message.replace(/[\r\n]+$/, "");
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
				info.statsElements.jobInfo.classList.add("job-info-done");
				this.jobs.markFinished(ident);
			} else if (
				/^CRITICAL (Sorry|Please report)|^ERROR Fatal exception|No space left on device|^Fatal Python error:|^(Thread|Current thread) 0x/.test(
					line,
				)
			) {
				info.statsElements.jobInfo.classList.add("job-info-fatal");
				this.jobs.markFatalException(ident);
			} else if (/Script requested immediate stop|^Adjusted target WARC path to.*-aborted$/.test(line)) {
				// Note: above message can be in:
				// ERROR Script requested immediate stop
				// or after an ERROR Fatal exception:
				// wpull.hook.HookStop: Script requested immediate stop.
				//
				// Also check for "Adjusted target WARC path" because
				// the exception may be entirely missing.
				info.statsElements.jobInfo.classList.remove("job-info-fatal");
				info.statsElements.jobInfo.classList.add("job-info-aborted");
			} else if (/^Received item /.test(line)) {
				// Clear other statuses if a job restarts with the same job ID
				info.statsElements.jobInfo.classList.remove("job-info-done");
				info.statsElements.jobInfo.classList.remove("job-info-fatal");
				info.statsElements.jobInfo.classList.remove("job-info-aborted");
				this.jobs.markUnfinished(ident);
			}
		}
		return renderedLines;
	}

	handleData(data) {
		const jobData = data.job_data;
		const added = this.jobs.handleJobData(jobData);
		this.numCrawls.textContent = this.jobs.countActive();
		if (added) {
			this._createLogContainer(jobData);
		}
		const type = data.type;
		const ident = jobData.ident;

		const info = this.renderInfo[ident];
		if (!info) {
			console.warn(`No render info for ${ident}`);
			return;
		}

		const totalResponses = parseInt(getTotalResponses(jobData));
		let linesRendered;
		if (type === "download") {
			linesRendered = this._renderDownloadLine(data, info.logSegment);
		} else if (type === "stdout") {
			linesRendered = this._renderStdoutLine(data, info.logSegment, info, ident);
		} else if (type === "ignore") {
			linesRendered = this._renderIgnoreLine(data, info.logSegment);
		} else {
			assert(false, `Unexpected message type ${type}`);
		}

		// Update stats
		info.statsElements.mb.textContent = numberWithCommas(
			toStringTenths((parseInt(jobData.bytes_downloaded) / (1000 * 1000)).toString()),
		);
		info.statsElements.responses.textContent = `${numberWithCommas(totalResponses)} resp.`;
		info.statsElements.responses.title = getSummaryResponses(jobData);
		const duration = Date.now() / 1000 - parseFloat(jobData.started_at);
		info.statsElements.responsesPerSecond.textContent = toStringTenths(totalResponses / duration);

		if (jobData.items_queued && jobData.items_downloaded) {
			const totalQueued = parseInt(jobData.items_queued, 10);
			const totalDownloaded = parseInt(jobData.items_downloaded, 10);
			info.statsElements.queueLength.textContent = numberWithCommas(`${totalQueued - totalDownloaded} in q.`);
			info.statsElements.queueLength.title = `${numberWithCommas(totalQueued)} queued\n${numberWithCommas(
				totalDownloaded,
			)} downloaded`;
		}

		info.statsElements.connections.textContent = jobData.concurrency;

		const delayMin = parseInt(jobData.delay_min);
		const delayMax = parseInt(jobData.delay_max);
		info.statsElements.delay.textContent = `${delayMin === delayMax ? delayMin : `${delayMin}-${delayMax}`} ms delay`;

		if (jobData.suppress_ignore_reports) {
			info.statsElements.ignores.textContent = "igoff";
			if (!info.statsElements.ignores.classList.contains("job-igoff")) {
				info.statsElements.ignores.classList.add("job-igoff");
			}
		} else {
			info.statsElements.ignores.textContent = "igon";
			if (info.statsElements.ignores.classList.contains("job-igoff")) {
				info.statsElements.ignores.classList.remove("job-igoff");
			}
		}

		// Update note
		info.jobNote.textContent = isBlank(jobData.note) ? "" : ` (${jobData.note})`;
		if (isBlank(jobData.note)) {
			info.jobUrl.removeAttribute("title");
		} else {
			info.jobUrl.title = jobData.note;
		}

		info.lineCountWindow += linesRendered;
		info.lineCountSegments[info.lineCountSegments.length - 1] += linesRendered;

		if (info.lineCountSegments[info.lineCountSegments.length - 1] >= this.linesPerSegment) {
			//console.log("Created new segment", info);
			const newSegment = this._createLogSegment();
			info.logWindow.appendChild(newSegment);
			info.logSegment = newSegment;
			info.lineCountSegments.push(0);
		}

		if (this.mouseInside !== ident) {
			// Don't remove any scrollback information when the job has a fatal exception,
			// so that the user can find the traceback and report a bug.
			if (!this.jobs.hasFatalException(ident)) {
				// We may have to remove more than one segment, if the user
				// has paused the log window for a while.
				while (info.lineCountWindow >= this.historyLines + this.linesPerSegment) {
					const firstLogSegment = info.logWindow.firstChild;
					assert(
						firstLogSegment != null,
						`info.logWindow.firstChild is null; ${JSON.stringify({
							lineCountWindow: info.lineCountWindow,
							lineCountSegments: info.lineCountSegments,
						})}`,
					);
					info.logWindow.removeChild(firstLogSegment);
					info.lineCountWindow -= info.lineCountSegments[0];
					info.lineCountSegments.shift();
				}
			}

			// If hidden, don't scroll: this saves us reflows and half our CPU time in Firefox.
			if (!info.logWindow.classList.contains("log-window-hidden")) {
				scrollToBottom(info.logWindow);
			}
		}
	}

	applyFilter() {
		const query = RegExp(this.filterBox.value);
		let matches = 0;
		const matchedWindows = [];
		const unmatchedWindows = [];
		this.firstFilterMatch = null;
		for (const job of this.jobs.sorted) {
			const w = this.renderInfo[job.ident].logWindow;
			const show = query.test(job.url) ||
			(this.showNicks && query.test(job.started_by));
			if (!show) {
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
		unmatchedWindows.map(classRemover("log-window-expanded"));
		matchedWindows.map(classRemover("log-window-expanded"));
		if (matches === 1) {
			matchedWindows.map(classAdder("log-window-expanded"));
		}

		if (matches < this.jobs.sorted.length) {
			// If you're not seeing all of the log windows, you're probably seeing very
			// few of them, so you probably want alignment enabled.
			this.setAligned(true);
		} else {
			// You're seeing all of the log windows, so alignment doesn't help as much
			// as seeing the full info.
			this.setAligned(false);
		}

		// Hidden log windows aren't scrolled down while lines are added to them,
		// but now that more are visible, we need to scroll them to the bottom.
		for (const w of matchedWindows) {
			// Don't scroll log windows we're mousing over
			if (w.classList.contains("log-window-stopped")) {
				continue;
			}
			scrollToBottom(w);
		}
	}

	showNextPrev(offset) {
		let idx;
		if (this.firstFilterMatch == null) {
			idx = null;
		} else {
			idx = this.jobs.sorted.findIndex((el) => {
				return el.ident === this.firstFilterMatch.ident;
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
		if (idx === -1) {
			idx = this.jobs.sorted.length;
		} else if (idx === this.jobs.sorted.length + 1) {
			idx = 0;
		}
		if (idx === this.jobs.sorted.length) {
			ds.setFilter("^$");
		} else {
			const newShownJob = this.jobs.sorted[idx];
			ds.setFilter(`^${regExpEscape(newShownJob.url)}$`);
		}
	}

	setAligned(aligned) {
		if (this._aligned === aligned) {
			return;
		}
		this._aligned = aligned;
		const adderOrRemover = aligned ? classAdder : classRemover;
		Array.from(document.querySelectorAll(".job-url")).map(adderOrRemover("job-url-aligned"));
		Array.from(document.querySelectorAll(".job-note")).map(adderOrRemover("job-note-aligned"));
		Array.from(document.querySelectorAll(".job-nick")).map(adderOrRemover("job-nick-aligned"));
		Array.from(document.querySelectorAll(".job-mb")).map(adderOrRemover("job-mb-aligned"));
		Array.from(document.querySelectorAll(".job-responses")).map(adderOrRemover("job-responses-aligned"));
		Array.from(document.querySelectorAll(".job-responses-per-second")).map(
			adderOrRemover("job-responses-per-second-aligned"),
		);
		Array.from(document.querySelectorAll(".job-in-queue")).map(adderOrRemover("job-in-queue-aligned"));
		Array.from(document.querySelectorAll(".job-connections")).map(adderOrRemover("job-connections-aligned"));
		Array.from(document.querySelectorAll(".job-delay")).map(adderOrRemover("job-delay-aligned"));
	}

	toggleAlign() {
		this.setAligned(!this._aligned);
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
		this.element = byId("context-menu");
	}

	/**
	 * Returns true if the event target is a URL in a log window
	 */
	clickedOnLogWindowURL(ev) {
		const cn = ev.target.className;
		return (
			cn === "line-normal" || cn === "line-error" || cn === "line-warning" || cn === "line-redirect" || cn === "log-url"
		);
	}

	makeCopyTextFn(text) {
		return () => {
			const clipboardScratchpad = byId("clipboard-scratchpad");
			clipboardScratchpad.value = text;
			clipboardScratchpad.focus();
			clipboardScratchpad.select();
			document.execCommand("copy");
		};
	}

	getPathVariants(fullPath) {
		const paths = [fullPath];
		// Avoid generating a near-duplicate suggestion with just the trailing slash removed
		let path = fullPath.replace(/\/$/, "");
		while (path && path.lastIndexOf("/") !== -1) {
			path = path.replace(/\/[^\/]*$/, "");
			paths.push(`${path}/`);
		}
		return paths;
	}

	getSuggestedCommands(ident, url, maxSuggestedIgnores) {
		// For testing a URL with enough path segments to cause [N more ignore suggestions]
		// url = "https://example.com/asset/620787/liveblog/api/cms/modules/cms/modules/cms/modules/cms/modules/cms/modules/cms/modules/";
		const schema = url.split(":")[0];
		const domain = url.split("/")[2];
		const withoutQuery = url.split("?")[0];
		const path = `/${split(withoutQuery, "/", 3)[3]}`;
		const reSchema = schema.startsWith("http") ? "https?" : "ftp";
		const pathVariants = this.getPathVariants(path);
		let somePathVariants = pathVariants.slice(-maxSuggestedIgnores);
		let ignoresRemaining = pathVariants.length - somePathVariants.length;
		// If only 1 more suggested ignore available, just put it in the context menu
		// to avoid a [... more ignore suggestions] taking up the same amount of space.
		if (ignoresRemaining === 1) {
			somePathVariants = pathVariants;
			ignoresRemaining = 0;
		}
		return [
			ignoresRemaining,
			somePathVariants
				.map((p) => {
					return `!ig ${ident} ^${reSchema}://${regExpEscape(domain + p)}`;
				})
				.concat([`!d ${ident} 180000 180000`, `!d ${ident} 250 375`, `!con ${ident} 1`]),
		];
	}

	makeEntries(ident, url, maxSuggestedIgnores) {
		const [ignoresRemaining, commands] = this.getSuggestedCommands(ident, url, maxSuggestedIgnores);
		const entries = [];
		// Unfortunately, this does not open it in a background tab
		// like the real context menu does.
		entries.push(h("a", { href: url }, "Open link in new tab"));
		entries.push(h("span", { onclick: this.makeCopyTextFn(url) }, "Copy link address"));
		if (ignoresRemaining) {
			entries.push(
				h(
					"span",
					{
						onclick: (ev) => {
							ev.stopPropagation();
							this.resetEntries(ident, url, maxSuggestedIgnores + 6);
						},
					},
					`[${ignoresRemaining} more ignore suggestion${ignoresRemaining === 1 ? "" : "s"}]`,
				),
			);
		}
		for (const c of commands) {
			entries.push(h("span", { onclick: this.makeCopyTextFn(c) }, `Copy ${c.replace(` ${ident} `, " … ")}`));
		}
		return entries;
	}

	resetEntries(ident, url, maxSuggestedIgnores) {
		console.log("resetEntries", ident, url, maxSuggestedIgnores);
		removeChildren(this.element);
		// We put the clipboard-scratchpad in the fixed-positioned
		// context menu instead of elsewhere on the page, because
		// we must focus the input box to automatically copy its text,
		// and the focus operation scrolls to the element on the page,
		// and we want to avoid such scrolling.
		appendAny(this.element, h("input", { type: "text", id: "clipboard-scratchpad" }));

		const entries = this.makeEntries(ident, url, maxSuggestedIgnores);
		for (const entry of entries) {
			entry.classList.add("context-menu-entry");
			appendAny(this.element, entry);
		}
	}

	onContextMenu(ev) {
		if (!this.clickedOnLogWindowURL(ev)) {
			this.blur();
			return;
		}
		ev.preventDefault();
		this.visible = true;
		this.element.style.display = "block";
		this.element.style.left = `${ev.clientX}px`;
		this.element.style.top = `${ev.clientY}px`;

		const ident = ev.target.parentNode.parentNode.parentNode.id.match(/^log-window-(.*)/)[1];
		// Get the URL from the .textContent instead of the .href because
		// browsers URL-encode characters like { } ^ as they are added to
		// the DOM, while we want the original, unescaped characters to create
		// the correct ignore pattern.
		const url = ev.target.textContent;
		const maxSuggestedIgnores = 8;
		this.resetEntries(ident, url, maxSuggestedIgnores);

		// If the bottom of the context menu is outside the viewport, move the context
		// menu up, so that it appears to have opened from its bottom-left corner.
		// + 1 pixel so that the pointer lands inside the element and turns on cursor: default
		if (ev.clientY + this.element.offsetHeight > document.documentElement.clientHeight) {
			this.element.style.top = `${ev.clientY - this.element.offsetHeight + 1}px`;
		}
	}

	blur() {
		this.visible = false;
		this.element.style.display = "none";
		this.callAfterBlurFns.map((fn) => fn());
		this.callAfterBlurFns = [];
	}

	// TODO: decouple - fire an onblur event instead
	callAfterBlur(fn) {
		this.callAfterBlurFns.push(fn);
	}
}

class BatchingQueue {
	// `callable` is the function to call with the entire queue when we've waited enough
	// time (`minInterval` milliseconds) or have enough items (`maxItems`).
	//
	// We need the second mechanism (`maxItems`) only because Chromium-based browsers
	// have aggressive timer throttling and quickly stop handling a "recursive" setTimeout
	// when the tab is in the background. Meanwhile, the page isn't entirely strangled:
	// WebSocket messages keep getting pumped in, leading to (without this mechanism)
	// over 100K unprocessed messages in the queue.
	constructor(callable, minInterval, maxItems) {
		this.callable = callable;
		this._minInterval = minInterval;
		this._maxItems = maxItems;
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
		if (this.queue.length >= this._maxItems) {
			this.callNow();
		} else if (this._timeout === null) {
			this._timeout = setTimeout(() => this._runCallable(), this._minInterval);
		}
	}
}

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
}

class RateTracker {
	constructor(keepReadings) {
		this._idx = 0;
		this._durations = new Array(keepReadings).fill(0);
		this._values = new Array(keepReadings).fill(0);
		this._keepReadings = keepReadings;
		this._timeLast = Date.now() / 1000;
	}

	_addReading(duration, value) {
		const idx = this._idx;
		this._durations[idx] = duration;
		this._values[idx] = value;
		// Loop back to 0 when we reach the end
		this._idx = (idx + 1) % this._keepReadings;
	}

	getRate(value) {
		const now = Date.now() / 1000;
		const duration = now - this._timeLast;
		this._timeLast = Date.now() / 1000;
		this._addReading(duration, value);
		let valueSum = 0;
		let durationSum = 0;
		for (let i = 0; i < this._keepReadings; i++) {
			valueSum += this._values[i];
			durationSum += this._durations[i];
		}
		return valueSum / durationSum;
	}
}

function isUblockOriginDoingCosmeticFiltering() {
	const adbox = document.querySelector(".adbox");
	return adbox.offsetHeight === 0;
}

class Dashboard {
	constructor() {
		if (isUblockOriginDoingCosmeticFiltering()) {
			byId("read-the-help").style.display = "block";
		}

		// We automatically scroll log windows to the bottom as lines are added,
		// and for performance reasons we have `content-visibility: auto` to skip
		// rendering when they are outside the viewport (at least in Chrome where
		// this CSS property is supported).
		//
		// However, when they are outside the viewport, they fail to get scrolled
		// to the bottom by `scrollToBottom` because they aren't rendering anything.
		// Listen to contentvisibilityautostatechange and scroll these log windows
		// to the bottom after they go back into the viewport and their rendering
		// is no longer being skipped.
		document.body.addEventListener("contentvisibilityautostatechange", (ev) => {
			if (!ev.skipped && ev.target.classList.contains("log-window")) {
				scrollToBottom(ev.target);
			}
		});

		this.messageCount = 0;
		this.newItemsReceived = 0;
		this.newBytesReceived = 0;

		const args = Object.fromEntries(new URLSearchParams(window.location.search));

		const historyLines = args.historyLines ? Number(args.historyLines) : navigator.userAgent.match(/Mobi/) ? 250 : 500;
		const batchTimeWhenVisible = args.batchTimeWhenVisible ? Number(args.batchTimeWhenVisible) : 125;
		// Note that setting batchTimeWhenHidden below 1000ms doesn't really do anything in Chrome, Firefox, and Safari
		// because (with normal settings) they don't run timers in background tabs more than once every 1000ms.
		const batchTimeWhenHidden = args.batchTimeWhenHidden ? Number(args.batchTimeWhenHidden) : 1000;
		const batchMaxItems = args.batchMaxItems ? Number(args.batchMaxItems) : 250;
		const showNicks = args.showNicks ? Boolean(Number(args.showNicks)) : false;
		const contextMenu = args.contextMenu ? Boolean(Number(args.contextMenu)) : true;
		this.initialFilter = args.initialFilter ?? "^$";
		const showAllHeaders = args.showAllHeaders ? Boolean(Number(args.showAllHeaders)) : true;
		const loadRecent = args.loadRecent ? Boolean(Number(args.loadRecent)) : true;
		this.debug = args.debug ? Boolean(Number(args.debug)) : false;

		// Append to page title to make it possible to identify the tab in Chrome's task manager
		if (args.title) {
			document.title += ` - ${args.title}`;
		}

		this.host = args.host ? args.host : location.hostname;
		this.dumpTraffic = args.dumpMax && Number(args.dumpMax) > 0;
		if (this.dumpTraffic) {
			this.dumpMax = Number(args.dumpMax);
		}

		this.contextMenuRenderer = new ContextMenuRenderer(document);
		if (contextMenu) {
			document.oncontextmenu = (ev) => this.contextMenuRenderer.onContextMenu(ev);
			document.onclick = (ev) => this.contextMenuRenderer.blur(ev);
			// onkeydown picks up ESC, onkeypress doesn't (tested Chrome 44)
			document.onkeydown = (ev) => {
				if (ev.keyCode === 27 /* ESC */) {
					this.contextMenuRenderer.blur();
				}
			};
			document.onwheel = () => this.contextMenuRenderer.blur();
		}

		this.jobsRenderer = new JobsRenderer(
			byId("logs"),
			byId("filter-box"),
			historyLines,
			showNicks,
			this.contextMenuRenderer,
		);

		document.onkeypress = (ev) => this.keyPress(ev);

		// Adjust help text based on URL
		Array.prototype.slice.call(document.querySelectorAll(".url-q-or-amp")).map((elem) => {
			if (window.location.search.indexOf("?") !== -1) {
				elem.textContent = "&";
			}
		});

		if (!showNicks) {
			addPageStyles(".job-nick-aligned { width: 0; }");
		}

		if (args.initialFilter != null) {
			byId("set-filter-none").after(
				h("input", {
					className: "button",
					type: "button",
					id: "set-filter-initial",
					onclick: () => { ds.setFilter(ds.initialFilter) },
					value: "Initial",
				})
			);
			byId("set-filter-none").after("\n");
		}
		this.setFilter(this.initialFilter);

		this.showAllHeaders(showAllHeaders);

		const finishSetup = () => {
			byId("meta-info").innerHTML = "";

			const rateRefreshInterval = 1000;
			const keepReadings = Math.round(5000 / rateRefreshInterval);
			const messagesRate = new RateTracker(keepReadings);
			const bytesRate = new RateTracker(keepReadings);

			// Keep this outside the BatchingQueue callable so that we detect
			// when we stop receiving data entirely.
			setInterval(() => {
				const msgPerSec = Math.round(messagesRate.getRate(this.newItemsReceived));
				const kbPerSec = Math.round(bytesRate.getRate(this.newBytesReceived / 1000));
				this.newItemsReceived = 0;
				this.newBytesReceived = 0;
				byId("meta-info").textContent = `WS:
${String(msgPerSec).padStart(3, "0")} msg/s,
${String(kbPerSec).padStart(3, "0")} KB/s`;
			}, rateRefreshInterval);

			this.queue = new BatchingQueue(
				(queue) => {
					if (this.debug) {
						console.log(`Processing ${queue.length} JSON messages`);
					}
					for (const obj of queue) {
						this.handleData(obj);
					}
				},
				batchTimeWhenVisible,
				batchMaxItems,
			);

			this.decayer = new Decayer(1000, 1.5, 60000);
			this.connectWebSocket();

			document.addEventListener(
				"visibilitychange",
				() => {
					if (document.hidden) {
						if (this.debug) {
							console.log(`Page has become hidden, setting batch time to ${batchTimeWhenHidden}ms`);
						}
						this.queue.setMinInterval(batchTimeWhenHidden);
					} else {
						if (this.debug) {
							console.log(`Page has become visible, setting batch time to ${batchTimeWhenVisible}ms`);
						}
						this.queue.setMinInterval(batchTimeWhenVisible);
						this.queue.callNow();
					}
				},
				false,
			);
		};

		if (loadRecent) {
			// Continue even if we fail to get /logs/recent data
			this.loadRecent().finally(finishSetup);
		} else {
			finishSetup();
		}
	}

	loadRecent() {
		return new Promise((resolve, reject) => {
			byId("meta-info").textContent = "Requesting recent data";
			const xhr = new XMLHttpRequest();
			xhr.onload = () => {
				try {
					const recentLines = JSON.parse(xhr.responseText);
					for (const line of recentLines) {
						this.handleData(line);
					}
				} catch (e) {
					console.log("Failed to load /logs/recent data:", e);
				}
				resolve();
			};
			xhr.onerror = (ev) => {
				reject(ev);
			};
			xhr.onprogress = (ev) => {
				const percent = Math.round(100 * (ev.loaded / ev.total));
				const size_mb = Math.round((100 * ev.total) / 1e6) / 100;
				byId("meta-info").textContent = `Recent data: ${percent}% (${size_mb}MB)`;
			};
			xhr.open("GET", `//${this.host}/logs/recent?cb=${Date.now()}${Math.random()}`);
			xhr.setRequestHeader("Accept", "application/json");
			xhr.send("");
		});
	}

	keyPress(ev) {
		// If you press ctrl-f or alt-f in Firefox (tested: 41), it dispatches
		// the keypress event for 'f'.  We want only the modifier-free
		// keypresses.
		if (ev.ctrlKey || ev.altKey || ev.metaKey) {
			return;
		}
		// Check shiftKey only after handling '?', because you need shift for '?'
		if (ev.which === 63 /* ? */) {
			ds.toggleHelp();
			return;
		}
		if (ev.shiftKey) {
			return;
		}
		if (ev.which === 106 /* j */) {
			this.jobsRenderer.showNextPrev(1);
		} else if (ev.which === 107 /* k */) {
			this.jobsRenderer.showNextPrev(-1);
		} else if (ev.which === 97 /* a */) {
			ds.setFilter("");
		} else if (ev.which === 110 /* n */) {
			ds.setFilter("^$");
		} else if (ev.which === 102 /* f */) {
			ev.preventDefault();
			byId("filter-box").focus();
			byId("filter-box").select();
		} else if (ev.which === 105 /* i */) {
			ds.setFilter(ds.initialFilter);
		} else if (ev.which === 118 /* v */) {
			window.open(this.jobsRenderer.firstFilterMatch.url);
		} else if (ev.which === 104 /* h */) {
			ds.showAllHeaders(!byId("show-all-headers").checked);
		}
	}

	handleData(data) {
		this.messageCount += 1;
		if (this.dumpTraffic && this.messageCount <= this.dumpMax) {
			byId("traffic").appendChild(h("pre", null, prettyJson(data)));
		}
		this.jobsRenderer.handleData(data);
	}

	connectWebSocket() {
		const wsproto = window.location.protocol === "https:" ? "wss:" : "ws:";

		this.ws = new WebSocket(`${wsproto}//${this.host}:4568/stream`);

		this.ws.onmessage = (ev) => {
			this.newItemsReceived += 1;
			this.newBytesReceived += ev.data.length;
			this.queue.push(JSON.parse(ev.data));
		};

		this.ws.onopen = (ev) => {
			console.log("WebSocket opened:", ev);
			this.decayer.reset();
		};

		this.ws.onclose = (ev) => {
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
		const help = byId("help");
		if (help.classList.contains("undisplayed")) {
			help.classList.remove("undisplayed");
		} else {
			help.classList.add("undisplayed");
		}
	}

	getFilter() {
		return byId("filter-box").value;
	}

	setFilter(value) {
		byId("filter-box").value = value;
		byId("filter-box").onchange();
	}

	showAllHeaders(value) {
		byId('show-all-headers').checked = value;
		byId('hide-headers').sheet.disabled = value;
	}
}

const ds = new Dashboard();
