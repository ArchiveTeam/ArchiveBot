(function () { "use strict";
var LogLine = function() {
};
LogLine.__name__ = true;
LogLine.prototype = {
	__class__: LogLine
};
var Job = function(ident) {
	this.downloadCountBucket = (function($this) {
		var $r;
		var _g = [];
		{
			var _g1 = 0;
			while(_g1 < 62) {
				var dummy = _g1++;
				_g.push(0);
			}
		}
		$r = _g;
		return $r;
	}(this));
	this.logLines = [];
	this.ident = ident;
};
Job.__name__ = true;
Job.prototype = {
	fillDownloadCountBucket: function() {
		var newDownloads = this.itemsDownloaded - this.lastDownloadCount;
		this.lastDownloadCount = this.itemsDownloaded;
		var currentSecond = new Date().getSeconds();
		this.downloadCountBucket[currentSecond] = newDownloads;
	}
	,computeSpeed: function() {
		var sum = 0;
		var _g = 0;
		var _g1 = this.downloadCountBucket;
		while(_g < _g1.length) {
			var count = _g1[_g];
			++_g;
			sum += count;
		}
		return sum / 60.0;
	}
	,__class__: Job
};
var Dashboard = function(hostname,maxScrollback,showNicks) {
	this.jobMap = new haxe.ds.StringMap();
	this.jobs = [];
	this.angular = angular;
	var _g = this;
	this.hostname = hostname;
	this.maxScrollback = maxScrollback;
	this.showNicks = showNicks;
	this.app = this.angular.module("dashboardApp",[]);
	var appConfig = ["$compileProvider",function(compileProvider) {
		compileProvider.debugInfoEnabled(false);
	}];
	this.app.config(appConfig);
	this.app.filter("bytes",function() {
		return function(num) {
			var _g1 = 0;
			var _g11 = ["B","KiB","MiB","GiB"];
			while(_g1 < _g11.length) {
				var unit = _g11[_g1];
				++_g1;
				if(num < 1024 && num > -1024) {
					num = Math.round(num * 10) / 10;
					return "" + num + " " + unit;
				}
				num /= 1024.0;
			}
			num = Math.round(num * 10) / 10;
			return "" + num + " TiB";
		};
	});
	var controllerArgs = ["$scope",function(scope) {
		scope.jobs = _g.jobs;
		scope.filterQuery = "";
		scope.hideDetails = false;
		scope.paused = false;
		scope.sortParam = "startedAt";
		scope.showNicks = showNicks;
		_g.dashboardControllerScopeApply = Reflect.field(scope,"$apply").bind(scope);
		scope.filterOperator = function(job) {
			var query = scope.filterQuery;
			return StringTools.startsWith(job.ident,query) || job.url.indexOf(query) != -1;
		};
		_g.dashboardControllerScope = scope;
	}];
	this.app.controller("DashboardController",controllerArgs);
};
Dashboard.__name__ = true;
Dashboard.getQueryArgs = function() {
	var query = window.location.search;
	var items = StringTools.replace(query,"?","").split("&");
	var args = new haxe.ds.StringMap();
	var _g = 0;
	while(_g < items.length) {
		var item = items[_g];
		++_g;
		var pairs = item.split("=");
		args.set(pairs[0],pairs[1]);
	}
	return args;
};
Dashboard.main = function() {
	var args = Dashboard.getQueryArgs();
	var hostname;
	var maxScrollback = 20;
	var showNicks = args.exists("showNicks");
	if(args.exists("host")) hostname = args.get("host"); else hostname = window.location.host;
	if(window.navigator.userAgent.indexOf("Mobi") == -1) maxScrollback = 500;
	var dashboard = new Dashboard(hostname,maxScrollback,showNicks);
	dashboard.run();
};
Dashboard.parseInt = function(thing) {
	if(Type["typeof"](thing) == ValueType.TInt || Type["typeof"](thing) == ValueType.TFloat) return thing; else if(thing != null) return Std.parseInt(thing); else return null;
};
Dashboard.prototype = {
	run: function() {
		this.loadRecentLogs();
	}
	,loadRecentLogs: function() {
		var _g = this;
		var request = new XMLHttpRequest();
		request.onerror = function(event) {
			_g.showError("Unable to load dashboard. Reload the page?");
		};
		request.onload = function(event1) {
			if(request.status != 200) {
				_g.showError("The server didn't respond correctly: " + request.status + " " + request.statusText);
				return;
			}
			_g.showError(null);
			var doc = JSON.parse(request.responseText);
			var _g1 = 0;
			while(_g1 < doc.length) {
				var logEvent = doc[_g1];
				++_g1;
				_g.processLogEvent(logEvent);
			}
			_g.scheduleDraw();
			_g.openWebSocket();
		};
		request.open("GET","http://" + this.hostname + "/logs/recent");
		request.setRequestHeader("Accept","application/json");
		request.send("");
	}
	,openWebSocket: function() {
		var _g = this;
		if(this.websocket != null) return;
		this.websocket = new WebSocket("ws://" + this.hostname + "/stream");
		this.websocket.onmessage = function(message) {
			_g.showError(null);
			var doc = JSON.parse(message.data);
			_g.processLogEvent(doc);
		};
		this.websocket.onclose = function(message1) {
			if(_g.websocket == null) return;
			_g.websocket = null;
			_g.showError("Lost connection. Reconnecting...");
			setTimeout(function() {
				_g.openWebSocket();
			},60000);
		};
		this.websocket.onerror = this.websocket.onclose;
	}
	,scheduleDraw: function(delayMS) {
		if(delayMS == null) delayMS = 1000;
		var _g = this;
		this.drawTimerHandle = setTimeout(function() {
			var delay = 1000;
			if(!window.document.hidden && !_g.dashboardControllerScope.paused) {
				var beforeDate = new Date();
				_g.redraw();
				var afterDate = new Date();
				var difference = afterDate.getTime() - beforeDate.getTime();
				if(difference > 10) {
					delay += difference * 5;
					delay = Math.min(delay,10000);
				}
			}
			_g.scheduleDraw(delay);
		},delayMS);
	}
	,processLogEvent: function(logEvent) {
		var job;
		var ident = logEvent.job_data.ident;
		if(!this.jobMap.exists(ident)) {
			job = new Job(ident);
			this.jobMap.set(ident,job);
			this.jobs.push(job);
			console.log("Load job " + ident);
		} else job = this.jobMap.get(ident);
		var jobData = logEvent.job_data;
		job.aborted = jobData.aborted;
		job.bytesDownloaded = Dashboard.parseInt(jobData.bytes_downloaded);
		job.concurrency = Dashboard.parseInt(jobData.concurrency);
		job.delayMax = Dashboard.parseInt(jobData.delay_max);
		job.delayMin = Dashboard.parseInt(jobData.delay_min);
		job.depth = jobData.depth;
		job.errorCount = Dashboard.parseInt(jobData.error_count);
		job.finished = jobData.finished;
		job.finishedAt = Dashboard.parseInt(jobData.finished_at);
		job.itemsDownloaded = Dashboard.parseInt(jobData.items_downloaded);
		job.itemsQueued = Dashboard.parseInt(jobData.items_queued);
		job.note = jobData.note;
		job.pipelineId = jobData.pipeline_id;
		job.queuedAt = Dashboard.parseInt(jobData.queued_at);
		job.r1xx = Dashboard.parseInt(jobData.r1xx);
		job.r2xx = Dashboard.parseInt(jobData.r2xx);
		job.r3xx = Dashboard.parseInt(jobData.r3xx);
		job.r4xx = Dashboard.parseInt(jobData.r4xx);
		job.r5xx = Dashboard.parseInt(jobData.r5xx);
		job.rUnknown = Dashboard.parseInt(jobData.runk);
		job.startedAt = Dashboard.parseInt(jobData.started_at);
		job.startedBy = jobData.started_by;
		job.startedIn = jobData.started_in;
		job.suppressIgnoreReports = jobData.suppress_ignore_reports;
		job.timestamp = Dashboard.parseInt(logEvent.ts);
		job.url = jobData.url;
		job.warcSize = jobData.warc_size;
		var logLine = new LogLine();
		logLine.type = logEvent.type;
		logLine.url = logEvent.url;
		logLine.timestamp = Dashboard.parseInt(logEvent.ts);
		logLine.isError = logEvent.is_error;
		logLine.isWarning = logEvent.is_warning;
		logLine.responseCode = logEvent.response_code;
		logLine.message = logEvent.message;
		logLine.pattern = logEvent.pattern;
		logLine.wgetCode = logEvent.wget_code;
		job.totalResponses = job.r1xx + job.r2xx + job.r3xx + job.r4xx + job.r1xx + job.errorCount;
		job.totalItems = job.itemsDownloaded + job.itemsQueued;
		if(job.logLines.length >= this.maxScrollback) job.logLines.shift();
		job.fillDownloadCountBucket();
		job.responsePerSecond = job.computeSpeed();
		job.logLines.push(logLine);
	}
	,showError: function(message) {
		var element = window.document.getElementById("message_box");
		if(message != null) {
			element.style.display = "block";
			element.innerText = message;
		} else element.style.display = "none";
	}
	,redraw: function() {
		this.dashboardControllerScopeApply();
		this.scrollLogsToBottom();
	}
	,scrollLogsToBottom: function() {
		var nodes = window.document.querySelectorAll(".autoscroll");
		var _g = 0;
		while(_g < nodes.length) {
			var node = nodes[_g];
			++_g;
			var element;
			element = js.Boot.__cast(node , Element);
			element.scrollTop += 1000;
		}
	}
	,__class__: Dashboard
};
var HxOverrides = function() { };
HxOverrides.__name__ = true;
HxOverrides.cca = function(s,index) {
	var x = s.charCodeAt(index);
	if(x != x) return undefined;
	return x;
};
HxOverrides.substr = function(s,pos,len) {
	if(pos != null && pos != 0 && len != null && len < 0) return "";
	if(len == null) len = s.length;
	if(pos < 0) {
		pos = s.length + pos;
		if(pos < 0) pos = 0;
	} else if(len < 0) len = s.length + len - pos;
	return s.substr(pos,len);
};
var IMap = function() { };
IMap.__name__ = true;
Math.__name__ = true;
var Reflect = function() { };
Reflect.__name__ = true;
Reflect.field = function(o,field) {
	try {
		return o[field];
	} catch( e ) {
		return null;
	}
};
var Std = function() { };
Std.__name__ = true;
Std.string = function(s) {
	return js.Boot.__string_rec(s,"");
};
Std.parseInt = function(x) {
	var v = parseInt(x,10);
	if(v == 0 && (HxOverrides.cca(x,1) == 120 || HxOverrides.cca(x,1) == 88)) v = parseInt(x);
	if(isNaN(v)) return null;
	return v;
};
var StringTools = function() { };
StringTools.__name__ = true;
StringTools.startsWith = function(s,start) {
	return s.length >= start.length && HxOverrides.substr(s,0,start.length) == start;
};
StringTools.replace = function(s,sub,by) {
	return s.split(sub).join(by);
};
var ValueType = { __ename__ : true, __constructs__ : ["TNull","TInt","TFloat","TBool","TObject","TFunction","TClass","TEnum","TUnknown"] };
ValueType.TNull = ["TNull",0];
ValueType.TNull.__enum__ = ValueType;
ValueType.TInt = ["TInt",1];
ValueType.TInt.__enum__ = ValueType;
ValueType.TFloat = ["TFloat",2];
ValueType.TFloat.__enum__ = ValueType;
ValueType.TBool = ["TBool",3];
ValueType.TBool.__enum__ = ValueType;
ValueType.TObject = ["TObject",4];
ValueType.TObject.__enum__ = ValueType;
ValueType.TFunction = ["TFunction",5];
ValueType.TFunction.__enum__ = ValueType;
ValueType.TClass = function(c) { var $x = ["TClass",6,c]; $x.__enum__ = ValueType; return $x; };
ValueType.TEnum = function(e) { var $x = ["TEnum",7,e]; $x.__enum__ = ValueType; return $x; };
ValueType.TUnknown = ["TUnknown",8];
ValueType.TUnknown.__enum__ = ValueType;
var Type = function() { };
Type.__name__ = true;
Type["typeof"] = function(v) {
	var _g = typeof(v);
	switch(_g) {
	case "boolean":
		return ValueType.TBool;
	case "string":
		return ValueType.TClass(String);
	case "number":
		if(Math.ceil(v) == v % 2147483648.0) return ValueType.TInt;
		return ValueType.TFloat;
	case "object":
		if(v == null) return ValueType.TNull;
		var e = v.__enum__;
		if(e != null) return ValueType.TEnum(e);
		var c;
		if((v instanceof Array) && v.__enum__ == null) c = Array; else c = v.__class__;
		if(c != null) return ValueType.TClass(c);
		return ValueType.TObject;
	case "function":
		if(v.__name__ || v.__ename__) return ValueType.TObject;
		return ValueType.TFunction;
	case "undefined":
		return ValueType.TNull;
	default:
		return ValueType.TUnknown;
	}
};
var haxe = {};
haxe.ds = {};
haxe.ds.StringMap = function() {
	this.h = { };
};
haxe.ds.StringMap.__name__ = true;
haxe.ds.StringMap.__interfaces__ = [IMap];
haxe.ds.StringMap.prototype = {
	set: function(key,value) {
		this.h["$" + key] = value;
	}
	,get: function(key) {
		return this.h["$" + key];
	}
	,exists: function(key) {
		return this.h.hasOwnProperty("$" + key);
	}
	,__class__: haxe.ds.StringMap
};
var js = {};
js.Boot = function() { };
js.Boot.__name__ = true;
js.Boot.getClass = function(o) {
	if((o instanceof Array) && o.__enum__ == null) return Array; else return o.__class__;
};
js.Boot.__string_rec = function(o,s) {
	if(o == null) return "null";
	if(s.length >= 5) return "<...>";
	var t = typeof(o);
	if(t == "function" && (o.__name__ || o.__ename__)) t = "object";
	switch(t) {
	case "object":
		if(o instanceof Array) {
			if(o.__enum__) {
				if(o.length == 2) return o[0];
				var str = o[0] + "(";
				s += "\t";
				var _g1 = 2;
				var _g = o.length;
				while(_g1 < _g) {
					var i = _g1++;
					if(i != 2) str += "," + js.Boot.__string_rec(o[i],s); else str += js.Boot.__string_rec(o[i],s);
				}
				return str + ")";
			}
			var l = o.length;
			var i1;
			var str1 = "[";
			s += "\t";
			var _g2 = 0;
			while(_g2 < l) {
				var i2 = _g2++;
				str1 += (i2 > 0?",":"") + js.Boot.__string_rec(o[i2],s);
			}
			str1 += "]";
			return str1;
		}
		var tostr;
		try {
			tostr = o.toString;
		} catch( e ) {
			return "???";
		}
		if(tostr != null && tostr != Object.toString) {
			var s2 = o.toString();
			if(s2 != "[object Object]") return s2;
		}
		var k = null;
		var str2 = "{\n";
		s += "\t";
		var hasp = o.hasOwnProperty != null;
		for( var k in o ) {
		if(hasp && !o.hasOwnProperty(k)) {
			continue;
		}
		if(k == "prototype" || k == "__class__" || k == "__super__" || k == "__interfaces__" || k == "__properties__") {
			continue;
		}
		if(str2.length != 2) str2 += ", \n";
		str2 += s + k + " : " + js.Boot.__string_rec(o[k],s);
		}
		s = s.substring(1);
		str2 += "\n" + s + "}";
		return str2;
	case "function":
		return "<function>";
	case "string":
		return o;
	default:
		return String(o);
	}
};
js.Boot.__interfLoop = function(cc,cl) {
	if(cc == null) return false;
	if(cc == cl) return true;
	var intf = cc.__interfaces__;
	if(intf != null) {
		var _g1 = 0;
		var _g = intf.length;
		while(_g1 < _g) {
			var i = _g1++;
			var i1 = intf[i];
			if(i1 == cl || js.Boot.__interfLoop(i1,cl)) return true;
		}
	}
	return js.Boot.__interfLoop(cc.__super__,cl);
};
js.Boot.__instanceof = function(o,cl) {
	if(cl == null) return false;
	switch(cl) {
	case Int:
		return (o|0) === o;
	case Float:
		return typeof(o) == "number";
	case Bool:
		return typeof(o) == "boolean";
	case String:
		return typeof(o) == "string";
	case Array:
		return (o instanceof Array) && o.__enum__ == null;
	case Dynamic:
		return true;
	default:
		if(o != null) {
			if(typeof(cl) == "function") {
				if(o instanceof cl) return true;
				if(js.Boot.__interfLoop(js.Boot.getClass(o),cl)) return true;
			}
		} else return false;
		if(cl == Class && o.__name__ != null) return true;
		if(cl == Enum && o.__ename__ != null) return true;
		return o.__enum__ == cl;
	}
};
js.Boot.__cast = function(o,t) {
	if(js.Boot.__instanceof(o,t)) return o; else throw "Cannot cast " + Std.string(o) + " to " + Std.string(t);
};
Math.NaN = Number.NaN;
Math.NEGATIVE_INFINITY = Number.NEGATIVE_INFINITY;
Math.POSITIVE_INFINITY = Number.POSITIVE_INFINITY;
Math.isFinite = function(i) {
	return isFinite(i);
};
Math.isNaN = function(i1) {
	return isNaN(i1);
};
String.prototype.__class__ = String;
String.__name__ = true;
Array.__name__ = true;
Date.prototype.__class__ = Date;
Date.__name__ = ["Date"];
var Int = { __name__ : ["Int"]};
var Dynamic = { __name__ : ["Dynamic"]};
var Float = Number;
Float.__name__ = ["Float"];
var Bool = Boolean;
Bool.__ename__ = ["Bool"];
var Class = { __name__ : ["Class"]};
var Enum = { };
Dashboard.main();
})();
