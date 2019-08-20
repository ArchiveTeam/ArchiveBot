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

        if (logLines.length >= maxScrollback) {
            logLines.shift();
        }

        fillDownloadCountBucket();
        responsePerSecond = computeSpeed();

        logLines.push(logLine);
        pendingLogLines += 1;
    }

    public function drawPendingLogLines() {
        if (pendingLogLines <= 0) {
            return;
        }

        var logElement = Browser.document.getElementById('job-log-${ident}');

        if (logElement == null) {
            return;
        }

        for (logLine in logLines.slice(-pendingLogLines)) {
            var logLineDiv = Browser.document.createDivElement();

            logLineDiv.className = "job-log-line";

            if (logLine.responseCode == 200) {
                logLineDiv.classList.add("text-success");
            } else if (logLine.isWarning) {
                logLineDiv.classList.add("bg-warning");
            } else if (logLine.isError) {
                logLineDiv.classList.add("bg-danger");
            } else if (logLine.message != null || logLine.pattern != null) {
                logLineDiv.classList.add("text-muted");
            }

            if (logLine.responseCode > 0 || logLine.wgetCode != null) {
                var text;
                if (logLine.responseCode > 0) {
                    text = '${logLine.responseCode} ';
                } else {
                    text = '${logLine.wgetCode} ';
                }
                logLineDiv.appendChild(Browser.document.createTextNode(text));
            }
            if (logLine.url != null) {
                var element = Browser.document.createAnchorElement();
                element.href = logLine.url;
                element.textContent = logLine.url;
                element.className = "job-log-line-url";
                logLineDiv.appendChild(element);

                if (logLine.pattern != null) {
                    var element = Browser.document.createSpanElement();
                    element.textContent = logLine.pattern;
                    element.className = "text-warning";
                    logLineDiv.appendChild(Browser.document.createTextNode(" "));
                    logLineDiv.appendChild(element);
                }
            } else if (logLine.message != null) {
                logLineDiv.textContent = logLine.message;
                logLineDiv.classList.add("job-log-line-message");
            }

            logElement.appendChild(logLineDiv);
        }

        var numToTrim = logElement.childElementCount - logLines.length;

        if (numToTrim > 0) {
            for (dummy in 0...numToTrim) {
                var child = logElement.firstChild;
                if (child != null) {
                    logElement.removeChild(child);
                }
            }
        }

        logElement.setAttribute("data-autoscroll-dirty", "true");
        pendingLogLines = 0;
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

    public static function main() {
        var args = getQueryArgs();
        var hostname;
        var maxScrollback = 20;
        var showNicks = args.exists("showNicks");

        if (args.exists("host")) {
            hostname = args.get("host");
        } else {
            hostname = Browser.location.hostname;
        }

        if (Browser.navigator.userAgent.indexOf("Mobi") == -1) {
            maxScrollback = 500;
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
                job.drawPendingLogLines();
            }
        }

        scrollLogsToBottom();
    }

    private function scrollLogsToBottom() {
        var nodes = Browser.document.querySelectorAll("[data-autoscroll-dirty].autoscroll");
        var pending = new Array<Element>();

        for (node in nodes) {
            var element:Element = cast(node, Element);
            element.removeAttribute("data-autoscroll-dirty");
            pending.push(element);
        }
        for (element in pending) {
            // Try to do layout in a tight loop
            element.scrollTop = 99999;
        }
    }
}
