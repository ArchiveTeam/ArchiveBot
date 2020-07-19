#!/bin/bash
for lang in De Es Fr Ru
do
	echo "${lang}"
	./mediawiki-lang.py mediawiki.json <(curl --silent --location https://github.com/wikimedia/mediawiki/raw/1.34.2/languages/messages/Messages${lang}.php) mediawiki-${lang,,} >mediawiki-${lang,,}.json
done
