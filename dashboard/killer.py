#!/usr/bin/python3

"""
dashboard/app.rb sometimes gets jammed up and hangs forever;
this utility kills it when it's unresponsive.  The restart is left up
to the for loop in your shell or your init system.

Usage:
./killer.py DASHBOARD_URL

If DASHBOARD_URL is not specified, http://127.0.0.1:4567/ will be used.
"""

import os
import sys
import time
import subprocess
import urllib.request as request

def kill_dashboard():
	print("\nKilling dashboard")
	try:
		pids = list(map(int, subprocess.check_output(["pgrep", "-f", "^ruby.*dashboard/app.rb"]).strip().split()))
	except KeyboardInterrupt:
		raise
	except:
		pids = []
	if len(pids) == 1:
		os.system('kill -9 %s' % (pids[0],))
	else:
		print("\nDid not kill, there were 0 or > 1 dashboard PIDs: %r" % (pids,))

def main():
	try:
		url = sys.argv[1]
	except IndexError:
		url = "http://127.0.0.1:4567/"
	while True:
		try:
			r = request.urlopen(url, timeout=10)
		except KeyboardInterrupt:
			raise
		except:
			body = ""
		else:
			body = r.read().decode("latin-1")	
		print(".", end=" ")
		sys.stdout.flush()
		if not body or "</body>" not in body:
			kill_dashboard()
		time.sleep(30)

if __name__ == '__main__':
	main()
