############################################################
# USE WITH CAUTION!
# May result in undesired behaviour, crashes, and wormholes.
############################################################

# Requirements:
# - Netcat with Unix socket support (e.g. the netcat-openbsd package on Debian/Ubuntu; not netcat-traditional; you can install both in parallel)
# - objgraph Python package. `pip3 install --user objgraph` (if you use venvs: in the venv that the AB process uses!)

# Usage:
# 1. "Pause" the affected job by increasing the delay to a large value (e.g. 3 minutes).
# 2. Wait until it's idle, i.e. not retrieving data anymore. (That's a bit tricky to verify. You could check the end of the log file or the open ArchiveBot/pipelines/tmp-* files of that process.
# 3. Figure out the PID of the process: `pgrep -f $jobid`
# 4. Run the script: `nc -U /tmp/manhole-$pid <cookiejar-empty-hack.py`
# 5. Wait for it to finish. Do not press ^C or similar.
# 6. "Unpause" the job by restoring the previous delay setting.

import objgraph

cjs = objgraph.by_type('wpull.cookie.BetterMozillaCookieJar')
if len(cjs) != 1:
	print('Not exactly one cookie jar')
else:
	# Ideally, we could just use .clear(), but that replaces the internal cookie dictionary and appears to break something in wpull.
	#cjs[0].clear()
	# So instead, explicitly delete the entry for each domain but keep the same object.
	for domain in list(cjs[0]._cookies): # Copy needed to allow modification during iteration
		del cjs[0]._cookies[domain]

exit()

#EOF
