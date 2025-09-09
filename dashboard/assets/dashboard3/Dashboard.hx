using StringTools;

import Std;
import haxe.ds.StringMap;
import js.Browser;
import js.html.XMLHttpRequest;
import haxe.Json;
import Reflect;
import js.html.WebSocket;
import js.html.Element;
import Math;
import Date;


class LogLine {
    public var type : String;
    public var wgetCode : String;
    public var isError : Bool;
    public var isWarning : Bool;
    public var url : String;
    public var timestamp : Int;
    public var responseCode : Int;
    public var message : String;
    public var pattern: String;

    public function new() {
    }
}

class Job {
    public var clusterize:Dynamic;
    private var clusterizeRows:Array<String> = [];

    public var ident : String;
    public var logLines : Array<LogLine> = [];
    public var aborted : Bool;
    public var bytesDownloaded : Int;
    public var itemsDownloaded : Int;
    public var itemsQueued : Int;
    public var pipelineId : String;
    public var depth:String;
    public var errorCount:Int;
    public var finished:Bool;
    public var finishedAt:Int;
    public var queuedAt:Int;
    public var startedAt:Int;
    public var startedBy:String;
    public var startedIn:String;
    public var url:String;
    public var warcSize:Int;
    public var suppressIgnoreReports:String;
    public var concurrency:Int;
    public var delayMin:Int;
    public var delayMax:Int;
    public var note:String;
    public var r1xx: Int;
    public var r2xx: Int;
    public var r3xx: Int;
    public var r4xx: Int;
    public var r5xx: Int;
    public var rUnknown: Int;
    public var timestamp:Int;
    public var responsePerSecond:Float;
    public var totalResponses:Int;
    public var queueRemaining:Int;
    public var logPaused:Bool;

    private var downloadCountBucket:Array<Int> = [for (dummy in 0...62) 0];
    private var lastDownloadCount:Int;
    private var pendingLogLines = 0;

    private static var isSafari = Browser.navigator.userAgent.indexOf("Safari") != -1;


    public function new(ident: String) {
        this.ident = ident;
    }

    private function fillDownloadCountBucket() {
        var newDownloads = itemsDownloaded - lastDownloadCount;
        lastDownloadCount = itemsDownloaded;

        var currentSecond = Date.now().getSeconds();
        downloadCountBucket[currentSecond] = newDownloads;
    }

    private function computeSpeed():Float {
        var sum = 0;
        for (count in downloadCountBucket) {
            sum += count;
        }

        return sum / 60.0;
    }

    private function getTextColor(logLine):String {
        // response codes:
        // 200 OK
        if (logLine.responseCode == 200) {
            return "text-success";
        }
        // 100s
        if (logLine.responseCode >= 100 && logLine.responseCode < 200) {
            return "text-primary";
        }
        // 200s (we already checked 200)
        if (logLine.responseCode >= 201 && logLine.responseCode < 300) {
            return "text-success-emphasis";
        }
        // 300s
        if (logLine.responseCode >= 300 && logLine.responseCode < 400) {
            return "text-info";
        }
        // 400s
        if (logLine.responseCode >= 400 && logLine.responseCode < 500) {
            return "text-warning";
        }
        // 500s
        if (logLine.responseCode >= 500 && logLine.responseCode < 600) {
            return "text-danger";
        }

        // warning levels / misc.
        if (logLine.isWarning) {
            return "text-warning";
        }
        if (logLine.isError) {
            return "text-danger";
        }
        if (logLine.message != null || logLine.pattern != null) {
            return "text-muted";
        }
        return "";  // fallback, no coloring
    }

    public function consumeLogEvent(logEvent:Dynamic, maxScrollback:Int) {
        var jobData:Dynamic = logEvent.job_data;

        aborted = jobData.aborted;
        bytesDownloaded = parseInt(jobData.bytes_downloaded);
        concurrency = parseInt(jobData.concurrency);
        delayMax = parseInt(jobData.delay_max);
        delayMin = parseInt(jobData.delay_min);
        depth = jobData.depth;
        errorCount = parseInt(jobData.error_count);
        finished = jobData.finished;
        finishedAt = parseInt(jobData.finished_at);
        itemsDownloaded = parseInt(jobData.items_downloaded);
        itemsQueued = parseInt(jobData.items_queued);
        note = jobData.note;
        pipelineId = jobData.pipeline_id;
        queuedAt = parseInt(jobData.queued_at);
        r1xx = parseInt(jobData.r1xx);
        r2xx = parseInt(jobData.r2xx);
        r3xx = parseInt(jobData.r3xx);
        r4xx = parseInt(jobData.r4xx);
        r5xx = parseInt(jobData.r5xx);
        rUnknown = parseInt(jobData.runk);
        startedAt = parseInt(jobData.started_at);
        startedBy = jobData.started_by;
        startedIn = jobData.started_in;
        suppressIgnoreReports = jobData.suppress_ignore_reports;
        timestamp = parseInt(logEvent.ts);
        url = jobData.url;
        warcSize = jobData.warc_size;

        var logLine = new LogLine();
        logLine.type = logEvent.type;
        logLine.url = logEvent.url;
        logLine.timestamp = parseInt(logEvent.ts);
        logLine.isError = logEvent.is_error;
        logLine.isWarning = logEvent.is_warning;
        logLine.responseCode = logEvent.response_code;
        logLine.message = logEvent.message;
        logLine.pattern = logEvent.pattern;
        logLine.wgetCode = logEvent.wget_code;

        totalResponses = r1xx + r2xx + r3xx + r4xx + r5xx + errorCount;
        queueRemaining = itemsQueued - itemsDownloaded;

        if (logLines.length > maxScrollback) {
            logLines = logLines.slice(logLines.length - maxScrollback);
        }

        fillDownloadCountBucket();
        responsePerSecond = computeSpeed();

        logLines.push(logLine);
        pendingLogLines += 1;
    }

    public function drawPendingLogLines(maxScrollback:Int) {
        if (pendingLogLines <= 0) {
            return;
        }

        var scrollEl = Browser.document.getElementById('job-log-${ident}');
        var contentEl = Browser.document.getElementById('job-log-content-${ident}');

        if (scrollEl == null || contentEl == null) {
            if (clusterize != null) {
                untyped clusterize.destroy(true);
                clusterize = null;
            }
            return;
        }

        if (clusterize != null) {
            var stale =
                (untyped clusterize.scroll_elem != scrollEl) ||
                (untyped clusterize.content_elem != contentEl);
            if (stale) {
                untyped clusterize.destroy(true);
                clusterize = null;
            }
        }

        if (clusterize == null) {
            clusterizeRows = [];
            var clusterizeOptions = {
                rows: [],
                scrollId: 'job-log-${ident}',
                contentId: 'job-log-content-${ident}'
            };
            clusterize = untyped __js__("new Clusterize")(clusterizeOptions);
        }

        for (logLine in logLines.slice(-pendingLogLines)) {
            var logColor = getTextColor(logLine);
            var text = "";

            if (logLine.responseCode > 0 || logLine.wgetCode != null) {
                if (logLine.responseCode > 0) {
                    text += '${logLine.responseCode} ';
                } else {
                    text += '${logLine.wgetCode} ';
                }
            }

            if (logLine.url != null) {
                text += '<a href="' + logLine.url + '" class="job-log-line-url">' + logLine.url + '</a>';
                if (logLine.pattern != null) {
                    text += ' <span class="text-warning">' + logLine.pattern + '</span>';
                }
            } else if (logLine.message != null) {
                text += '<span class="job-log-line-message">' + logLine.message + '</span>';
            }

            if (logColor != "") {
                text = '<div class="job-log-line ' + logColor + '">' + text + '</div>';
            } else {
                text = '<div class="job-log-line">' + text + '</div>';
            }

            clusterizeRows.push(text);
        }

        if (clusterizeRows.length > maxScrollback) {
            clusterizeRows = clusterizeRows.slice(clusterizeRows.length - maxScrollback);
        }

        untyped clusterize.update(clusterizeRows);
        pendingLogLines = 0;
    }

    public function enforceScrollback(maxScrollback:Int) {
        if (logLines.length > maxScrollback) {
            logLines = logLines.slice(logLines.length - maxScrollback);
        }
        if (clusterizeRows.length > maxScrollback) {
            clusterizeRows = clusterizeRows.slice(clusterizeRows.length - maxScrollback);
            if (clusterize != null) {
                untyped clusterize.update(clusterizeRows);
            }
        }
    }

    public function attachAntiScroll() {
        var logWindow = Browser.document.getElementById('job-log-${ident}');

        if (logWindow == null) {
            return;
        }

        if (logWindow.getAttribute("data-anti-scroll") == "attached") {
            return;
        }

        logWindow.setAttribute("data-anti-scroll", "attached");

        // If you reach the end of a log window, the browser annoyingly
        // starts to scroll the page instead.  We prevent this behavior here.
        // If the user wants to scroll the page, they need to move their
        // mouse outside a log window first.
        Reflect.setField(logWindow, "onwheel", function (ev) {
            // Note: offsetHeight is "wrong" by 2px but it doesn't matter
            //trace(ev, logWindow.scrollTop, (logWindow.scrollHeight - logWindow.offsetHeight));
            if (ev.deltaY < 0 && logWindow.scrollTop == 0) {
                ev.preventDefault();
            } else if(ev.deltaY > 0 && logWindow.scrollTop >= (logWindow.scrollHeight - logWindow.offsetHeight)) {
                ev.preventDefault();
            }
        });
    }

    private static function parseInt(thing:Dynamic):Int {
        if (thing != null) {
            try {
                return Std.parseInt(thing);
            } catch (error:Dynamic) {
                return thing;
            }
        } else {
            return null;
        }
    }
}


class Dashboard {
    var angular = untyped __js__("angular");
    var app:Dynamic;
    var jobs:Array<Job> = [];
    var jobMap:StringMap<Job> = new StringMap<Job>();
    var hostname:String;
    var dashboardControllerScope:Dynamic;
    var dashboardControllerScopeApply:Dynamic;
    var maxScrollback:Int;
    var websocket:js.html.WebSocket;
    var drawTimerHandle:Dynamic;
    var showNicks:Bool;
    var drawInterval:Int;

    public function new(hostname:String, maxScrollback:Int = 500, showNicks:Bool = false, drawInterval:Int = 1000) {
        this.hostname = hostname;
        this.maxScrollback = maxScrollback;
        this.showNicks = showNicks;
        this.drawInterval = drawInterval;

        app = angular.module("dashboardApp", []);

        var appConfig:Array<Dynamic> = [
        "$compileProvider",
            function (compileProvider) {
                compileProvider.debugInfoEnabled(false);
            }
        ];

        app.config(appConfig);

        app.filter("bytes", function () {
            return function (num:Float) {
                // http://stackoverflow.com/a/1094933/1524507
                for (unit in ['B', 'KiB', 'MiB', 'GiB']) {
                    if (num < 1024 && num > -1024) {
                        num = Math.round(num * 10) / 10;
                        return '$num $unit';
                    }

                    num /= 1024.0;
                }

                num = Math.round(num * 10) / 10;
                return '$num TiB';
            };
        });

        var controllerArgs:Array<Dynamic> = [
            "$scope",
            function (scope) {
                scope.jobs = this.jobs;
                scope.filterQuery = "";
                scope.hideDetails = false;
                scope.paused = false;
                scope.sortParam = "startedAt";
                scope.showNicks = showNicks;
                scope.drawInterval = drawInterval;
                scope.currentPage = 1;
                scope.pageSize = 20;
                scope.totalPages = 1;
                dashboardControllerScopeApply = Reflect.field(scope, "$apply").bind(scope);
                scope.filterOperator = function (job:Job) {
                    var query:String = scope.filterQuery;
                    if (scope.showNicks) {
                        return (job.ident.startsWith(query)
                            || job.url.indexOf(query) != -1
                            || job.startedBy.toLowerCase().indexOf(query.toLowerCase()) != -1);
                    } else {
                        return (job.ident.startsWith(query)
                            || job.url.indexOf(query) != -1);
                    }
                };
                dashboardControllerScope = scope;
                scope.applyFilterQuery = function (query:String) {
                    scope.filterQuery = query;
                }
                scope.$watchGroup(["filterQuery", "jobs.length"], function(newVals:Dynamic, oldVals:Dynamic) {
                    var filterQuery = newVals[0];

                    // update max scrollback when searching
                    var maxScrollback = 500;
                    if (filterQuery == null || filterQuery.trim() == "") {
                        maxScrollback = 50;
                    }
                    changeMaxScrollback(maxScrollback);
                    for (job in jobs) {
                        job.enforceScrollback(this.maxScrollback);
                    }

                    // pagination
                    var filtered = scope.jobs.filter(scope.filterOperator);
                    var pages:Float = Math.ceil(filtered.length / (scope.pageSize : Float));
                    scope.totalPages = Std.int(Math.max(1, pages));
                    if (oldVals != null && filterQuery != oldVals[0]) {
                        scope.currentPage = 1;
                    } else {
                        if (scope.currentPage > scope.totalPages) {
                            scope.currentPage = scope.totalPages;
                        }
                    }
                });
                scope.setPage = function (page:Int) {
                    if (page >= 1 && page <= scope.totalPages) {
                        scope.currentPage = page;
                    }
                };
            }
        ];

        app.controller("DashboardController", controllerArgs);

    }

    public static function getQueryArgs():StringMap<String> {
        var query:String = Browser.location.search;
        var items = query.replace("?", "").split("&");

        var args = new StringMap<String>();

        for (item in items) {
            var pairs = item.split("=");
            args.set(pairs[0], pairs[1]);
        }

        return args;
    }

    public function changeMaxScrollback(maxScrollback:Int) {
        this.maxScrollback = maxScrollback;
        return;
    }

    public static function main() {
        var args = getQueryArgs();
        var hostname;
        var maxScrollback = 50;
        var showNicks = args.exists("showNicks");

        if (args.exists("host")) {
            hostname = args.get("host");
        } else {
            hostname = Browser.location.hostname;
        }

        var dashboard = new Dashboard(hostname, maxScrollback, showNicks);
        dashboard.run();
    }

    private function run() {
        loadRecentLogs();
    }

    private function loadRecentLogs() {
        var request = new XMLHttpRequest();

        request.onerror = function(event:Dynamic) {
            showError("Unable to load dashboard. Reload the page?");
        };

        request.onload = function (event:Dynamic) {
            if (request.status != 200) {
                showError('The server didn\'t respond correctly: ${request.status} ${request.statusText}');
                return;
            }

            showError(null);

            var doc:Array<Dynamic> = Json.parse(request.responseText);

            for (logEvent in doc) {
                processLogEvent(logEvent);
            }

            scheduleDraw();
            openWebSocket();
        };
        var cacheBustValue = Date.now().getTime();

        request.open("GET", '/logs/recent?cb=$cacheBustValue');
        request.setRequestHeader("Accept", "application/json");
        request.send("");
    }

    private function openWebSocket() {
        if (websocket != null) {
            return;
        }

        var wsProto = Browser.location.protocol == "https:" ? "wss:" : "ws:";

        websocket = new WebSocket('$wsProto//$hostname:4568/stream');

        websocket.onmessage = function (message:Dynamic) {
            showError(null);

            var doc:Dynamic = Json.parse(message.data);
            processLogEvent(doc);
        };

        websocket.onclose = function (message:Dynamic) {
            if (websocket == null) {
                return;
            }

            websocket = null;
            showError("Lost connection. Reconnecting...");

            untyped __js__("setTimeout")(function () {
                openWebSocket();
            }, 60000);
        }
        websocket.onerror = websocket.onclose;
    }

    private function scheduleDraw(delayMS:Int = 1000) {
        drawTimerHandle = untyped __js__("setTimeout")(function () {
            var delay:Int = dashboardControllerScope.drawInterval;

            if (!Browser.document.hidden && !dashboardControllerScope.paused) {
                var beforeDate = Date.now();
                redraw();
                var afterDate = Date.now();

                var difference = afterDate.getTime() - beforeDate.getTime();

                if (difference > 10) {
                    delay += difference * 2;
                    delay = Math.min(delay, 10000);
                }
            }

            scheduleDraw(delay);
        }, delayMS);
    }

    private function processLogEvent(logEvent:Dynamic) {
        var job:Job;
        var ident:String = logEvent.job_data.ident;

        if (!jobMap.exists(ident)) {
            job = new Job(ident);
            jobMap.set(ident, job);
            jobs.push(job);

            trace('Load job $ident');
        } else {
            job = jobMap.get(ident);
        }

        job.consumeLogEvent(logEvent, maxScrollback);
    }

    private function showError(message:String) {
        var element = Browser.document.getElementById("message_box");

        if (message != null) {
            element.style.display = "block";
            element.innerText = message;
        } else {
            element.style.display = "none";
        }
    }

    private function redraw() {
        dashboardControllerScopeApply();

        for (job in jobs) {
            if (!job.logPaused) {
                job.drawPendingLogLines(maxScrollback);
            }
        }

        scrollLogsToBottom();
    }

    private function scrollLogsToBottom() {
        for (job in jobs) {
            if (!job.logPaused && job.clusterize != null) {
                var scrollEl = Browser.document.getElementById('job-log-${job.ident}');
                if (scrollEl != null) {
                    scrollEl.scrollTop = scrollEl.scrollHeight;
                }
            }
        }
    }
}
