#!/usr/bin/python2

import os
import sys
import time
import urllib

try:
    url = sys.argv[1]
except IndexError:
    url = "http://127.0.0.1:4567/"

try:
    r = urllib.urlopen(url)
except KeyboardInterrupt:
    raise
except:
    body = ""
else:
    body = r.read().decode("latin-1")

if not body or "</body>" not in body:
    sys.exit(1)
else:
    sys.exit(0)
