#!/bin/bash
for lang in Ar Cs De Es Fr It Ja Ka Ko Nl Pt Ru Sl Sq Uk Zh
do
	echo "${lang}"
	./mediawiki-lang.py mediawiki.json <(curl --silent --location https://github.com/wikimedia/mediawiki/raw/1.34.2/languages/messages/Messages${lang}.php) mediawiki-${lang,,} >mediawiki-${lang,,}.json
done
