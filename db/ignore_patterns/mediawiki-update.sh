#!/bin/bash
for lang in Ar Bg Bs Ca Cs De El Eo Es Fa Fi Fr He It Ja Ka Ko Li Nl Pl Pt Ro Ru Sd Sl Sq Sv Th Tr Uk Zh
do
	echo "${lang}"
	./mediawiki-lang.py mediawiki.json <(curl --silent --location https://github.com/wikimedia/mediawiki/raw/1.34.2/languages/messages/Messages${lang}.php) mediawiki-${lang,,} >mediawiki-${lang,,}.json
done
