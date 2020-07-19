#!/usr/bin/env python3

import re
import urllib.parse
import sys


if len(sys.argv) != 4:
	print('Usage: mediawiki-lang.py IGSETFILE MEDIAWIKILANGFILE NEWNAME', file = sys.stderr)
	print(' IGSETFILE: an ignore set file in English', file = sys.stderr)
	print(" MEDIAWIKILANGFILE: one of the files in MediaWiki's languages/messages directory", file = sys.stderr)
	print(' NEWNAME: desired name attribute of the generated igset (must not contain quotes or other odd characters; recommended to only use [a-z-]+)', file = sys.stderr)
	sys.exit(1)

with open(sys.argv[1], 'r') as fp:
	englishIgset = fp.read()

with open(sys.argv[2], 'r') as fp:
	messagesOtherLang = fp.read()

newName = sys.argv[3]

# Extract locale's Special namespace name
if 'NS_SPECIAL' not in messagesOtherLang:
	raise RuntimeError('Failed to extract special namespace name')
specialAlias = urllib.parse.quote(re.search(r"NS_SPECIAL\s*=>\s*'([^']+)'", messagesOtherLang).group(1))

# Parse special page aliases
aliasesStr = re.search(r"\$specialPageAliases = \[(.*?)\];", messagesOtherLang, re.DOTALL).group(1)
aliases = {}
for line in aliasesStr.split('\n'):
	line = line.strip()
	if '=>' not in line:
		continue
	assert line.startswith("'")
	name = line[1:line.index("'", 1)].lower()
	aliases[name] = []
	valList = line[line.index('=>') + 2:].strip()
	assert valList.startswith('[')
	assert valList.endswith('],')
	for val in valList[1:-2].split(','):
		val = val.strip()
		assert val.startswith("'")
		assert val.endswith("'")
		aliases[name].append(urllib.parse.quote(val[1:-1]))

# Process igset
fragments = englishIgset.split('Special:')
igsetOtherLangList = []
igsetOtherLangList.append(fragments[0])
for frag in fragments[1:]:
	igsetOtherLangList.append(specialAlias)
	igsetOtherLangList.append(':')
	if frag.startswith('('):
		# Alternation
		alts, remainder = frag[1:].split(')', 1)
		igsetOtherLangList.append('(')
		for alt in alts.split('|'):
			altL = alt.lower()
			if altL in aliases:
				if len(aliases[altL]) > 1:
					igsetOtherLangList.append('(' + '|'.join(aliases[altL]) + ')')
				else:
					igsetOtherLangList.append(aliases[altL][0])
			else:
				igsetOtherLangList.append(alt)
			igsetOtherLangList.append('|')
		assert igsetOtherLangList.pop() == '|' # Remove the final |
		igsetOtherLangList.append(')')
		igsetOtherLangList.append(remainder)
	else:
		name = re.match('[A-Za-z]+', frag).group(0)
		nameL = name.lower()
		if nameL in aliases:
			if len(aliases[nameL]) > 1:
				igsetOtherLangList.append('(' + '|'.join(aliases[nameL]) + ')')
			else:
				igsetOtherLangList.append(aliases[nameL][0])
		else:
			igsetOtherLangList.append(name)
		igsetOtherLangList.append(frag[len(name):])

igsetOtherLang = ''.join(igsetOtherLangList)


# Other namespaces of note
for nsConst, enName in (('NS_CATEGORY', 'Category'), ('NS_USER', 'User'), ('NS_USER_TALK', 'User_talk')):
	if nsConst not in messagesOtherLang:
		continue
	nsAlias = urllib.parse.quote(re.search(nsConst + r"\s*=>\s*'([^']+)'", messagesOtherLang).group(1))
	igsetOtherLang = igsetOtherLang.replace(enName + ':', nsAlias + ':')


print(igsetOtherLang.replace('"name": "mediawiki"', f'"name": "{newName}"'), end = '')
