using StringTools;

import Std;
import Type;
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
    public var depth : String;
    public var errorCount : Int;
    public var finished : Bool;
    public var finishedAt : Int;
    public var queuedAt : Int;
    public var startedAt : Int;
    public var startedBy : String;
    public var startedIn : String;
    public var url : String;
    public var warcSize : Int;
    public var suppressIgnoreReports : String;
    public var concurrency : Int;
    public var delayMin : Int;
    public var delayMax : Int;
    public var note : String;
    public var r1xx: Int;
    public var r2xx: Int;
    public var r3xx: Int;
    public var r4xx: Int;
    public var r5xx: Int;
    public var rUnknown: Int;
    public var timestamp : Int;

    public function new(ident: String) {
        this.ident = ident;
    }
}


class Dashboard {
    var angular = untyped __js__("angular");
    var app : Dynamic;
    var jobs : Array<Job> = [];
    var jobMap : StringMap<Job> = new StringMap<Job>();
    var hostname : String;
    var dashboardControllerScope : Dynamic;
    var dashboardControllerScopeApply : Dynamic;
    var maxScrollback : Int;
    var websocket : js.html.WebSocket;
    var drawTimerHandle : Dynamic;
    var showNicks : Bool;

    public function new(hostname : String, maxScrollback : Int, showNicks : Bool) {
        this.hostname = hostname;
        this.maxScrollback = maxScrollback;
        this.showNicks = showNicks;

        app = angular.module("dashboardApp", []);

        var appConfig : Array<Dynamic> = [
        "$compileProvider",
            function (compileProvider) {
                compileProvider.debugInfoEnabled(false);
            }
        ];

        app.config(appConfig);

        app.filter("bytes", function () {
            return function (num : Float) {
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

        var controllerArgs : Array<Dynamic> = [
            "$scope",
            function (scope) {
                scope.jobs = this.jobs;
                scope.filterQuery = "";
                scope.hideDetails = false;
                scope.paused = false;
                scope.sortParam = "startedAt";
                scope.showNicks = showNicks;
                dashboardControllerScopeApply = Reflect.field(scope, "$apply").bind(scope);
                scope.filterOperator = function (job : Job) {
                    var query : String = scope.filterQuery;
                    return (job.ident.startsWith(query) || job.url.indexOf(query) != -1);
                };
                dashboardControllerScope = scope;
            }
        ];

        app.controller("DashboardController", controllerArgs);

    }

    public static function getQueryArgs() : StringMap<String> {
        var query : String = Browser.location.search;
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
            hostname = Browser.location.host;
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

        request.onerror = function(event : Dynamic) {
            showError("Unable to load dashboard. Reload the page?");
        };

        request.onload = function (event : Dynamic) {
            if (request.status != 200) {
                showError('The server didn\'t respond correctly: ${request.status} ${request.statusText}');
                return;
            }

            showError(null);

            var doc : Array<Dynamic> = Json.parse(request.responseText);

            for (logEvent in doc) {
                processLogEvent(logEvent);
            }

            scheduleDraw();
            openWebSocket();
        };

        request.open("GET", 'http://$hostname/logs/recent');
        request.setRequestHeader("Accept", "application/json");
        request.send("");
    }

    private function openWebSocket() {
        if (websocket != null) {
            return;
        }

        websocket = new WebSocket('ws://$hostname/stream');

        websocket.onmessage = function (message : Dynamic) {
            showError(null);

            var doc : Dynamic = Json.parse(message.data);
            processLogEvent(doc);
        };

        websocket.onclose = function (message : Dynamic) {
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

    private function scheduleDraw(delayMS : Int = 1000) {
        drawTimerHandle = untyped __js__("setTimeout")(function () {
            var delay = 1000;

            if (!Browser.document.hidden && !dashboardControllerScope.paused) {
                var beforeDate = Date.now();
                redraw();
                var afterDate = Date.now();

                var difference = afterDate.getTime() - beforeDate.getTime();

                if (difference > 10) {
                    delay += difference * 5;
                    delay = Math.min(delay, 10000);
                }
            }

            scheduleDraw(delay);
        }, delayMS);
    }

    private function processLogEvent(logEvent : Dynamic) {
        var job : Job;
        var ident : String = logEvent.job_data.ident;

        if (!jobMap.exists(ident)) {
            job = new Job(ident);
            jobMap.set(ident, job);
            jobs.push(job);

            trace('Load job $ident');
        } else {
            job = jobMap.get(ident);
        }

        var jobData : Dynamic = logEvent.job_data;

        job.aborted = jobData.aborted;
        job.bytesDownloaded = parseInt(jobData.bytes_downloaded);
        job.concurrency = parseInt(jobData.concurrency);
        job.delayMax = parseInt(jobData.delay_max);
        job.delayMin = parseInt(jobData.delay_min);
        job.depth = jobData.depth;
        job.errorCount = parseInt(jobData.error_count);
        job.finished = jobData.finished;
        job.finishedAt = parseInt(jobData.finished_at);
        job.itemsDownloaded = parseInt(jobData.items_downloaded);
        job.itemsQueued = parseInt(jobData.items_queued);
        job.note = jobData.note;
        job.pipelineId = jobData.pipeline_id;
        job.queuedAt = parseInt(jobData.queued_at);
        job.r1xx = parseInt(jobData.r1xx);
        job.r2xx = parseInt(jobData.r2xx);
        job.r3xx = parseInt(jobData.r3xx);
        job.r4xx = parseInt(jobData.r4xx);
        job.r5xx = parseInt(jobData.r5xx);
        job.rUnknown = parseInt(jobData.runk);
        job.startedAt = parseInt(jobData.started_at);
        job.startedBy = jobData.started_by;
        job.startedIn = jobData.started_in;
        job.suppressIgnoreReports = jobData.suppress_ignore_reports;
        job.timestamp = parseInt(logEvent.ts);
        job.url = jobData.url;
        job.warcSize = jobData.warc_size;

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

        if (job.logLines.length >= maxScrollback) {
            job.logLines.shift();
        }

        job.logLines.push(logLine);
    }

    private function showError(message : String) {
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
        scrollLogsToBottom();
    }

    private function scrollLogsToBottom() {
        var nodes = Browser.document.querySelectorAll(".autoscroll");
        for (node in nodes) {
            var element : Element = cast(node, Element);
            element.scrollTop += 1000;
        }
    }

    private static function parseInt(thing : Dynamic) : Int {
        if (Type.typeof(thing) == TInt || Type.typeof(thing) == TFloat) {
            return thing;
        } else if (thing != null) {
            return Std.parseInt(thing);
        } else {
            return null;
        }
    }
}
