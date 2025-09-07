all: dashboard

dashboard: Dashboard.hx
	haxe -main Dashboard -D analyzer-optimize -dce full -D js-es=6 -js dashboard3.js
