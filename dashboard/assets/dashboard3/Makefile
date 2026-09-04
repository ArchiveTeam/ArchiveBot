all: dashboard minify

dashboard: Dashboard.hx
	haxe -main Dashboard -D analyzer-optimize -dce full -D js-es=6 -js dashboard3.js

minify: dashboard3.js dashboard3.css ../../dashboard3.html
# npm i -g terser csso-cli html-minifier-next
	terser dashboard3.js -c -m --ecma 2015 -o dashboard3.min.js
	csso dashboard3.css -o dashboard3.min.css
	html-minifier-next --collapse-whitespace --minify-js true ../../dashboard3.html -o ../../dashboard3.min.html
