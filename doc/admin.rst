=========================
ArchiveBot Administration
=========================

ArchiveBot has a central "control node" server.  This document explains how to manage it, hopefully without breaking anything.

This control node server does many things. It runs the actual bot that sits in an IRC channel and listens to commands about which websites to archive. It runs the Redis server that keeps track of all the pipelines and their data. It runs the web-based ArchiveBot dashboard and pipeline dashboard. It runs the Twitter bot that sends information about what's being archived. It has access to log files and debug information.

It also handles many manual administrative tasks that need doing from time to time, such as cleaning out (or "reaping") information about old pipelines that have gone offline, or old web crawl jobs that were aborted or died or disappeared.

Another common administrative task on this server is manually adding new pipeline operators' SSH keys so that their pipelines can communicate with the dashboard and be assigned new tasks from the queue.


Basic Information
=================

The control node server is usually administrated by SSH.  Pipelines also connect over SSH, possibly with a separate account (e.g. ``pipeline``).


How to add new ArchiveBot pipelines
===================================

Pipelines run on their own servers. Each of these can handle several web crawls at a time, depending on their servers' individual configuration and their available hard drive space and memory.  More information and installation instructions are at GitHub:
https://github.com/ArchiveTeam/ArchiveBot/blob/master/INSTALL.pipeline

When a new pipeline is set up and all ready to go, the last step is that the server's SSH key still needs to be manually added to the control node. The new pipeline's operator should e-mail or private message one of the members with access to the control node server, who then need to open ``~/.ssh/authorized_keys`` for the relevant account with the text editor of their choice and add the new pipeline server's SSH key to the bottom of the list.  If the new pipeline is set up correctly, it should then show up on the web-based pipeline dashboard shortly after that, and should start being assigned web crawl jobs from the queue.


All about tmux
==============

The control node server has many different processes running constantly. To help keep these processes running even when people log in or out, and to keep things somewhat well-organized, the server is set up with a program called ``tmux`` to run multiple "windows" and "panes" of information.

When you log into the control node server, you should type ``tmux attach`` to view all the panes and easily move between them.

Here are some common tmux commands that can be helpful:

	* Control-B N - moves to the next window
	* Control-B C - create a new window
	* Control-B W – select a window (shows all running panes)
	* Control-B [0-9] – go to a specific number (numbered 0 through 9)
	* Control-B arrow – move between panes within a window
	* Control-B S – select an entirely different tmux session (although there should usually be just one)

Each pane has a process running in it, and related processes' panes are usually grouped in one window.


CouchDB and Redis
+++++++++++++++++

CouchDB and Redis might be running in tmux or as a system service, depending on how it was set up exactly. Either way, they can generally be ignored and left alone.


Dashboard
+++++++++

This window runs the dashboard components: the Ruby server (static files, job and pipeline list, etc.), the Python WebSocket server (real-time log delivery), and the Ruby server killer (``killer.py``).

The Ruby server pane logs warnings and errors occurring in the Ruby code but is generally relatively quiet.  The Python WebSocket server logs stats (number of connected users, queue size, CPU and memory usage) every minute.  The Ruby server has an unknown bug which renders it unresponsive.  ivan's dashboard killer regularly polls it to see if it's alive, and it prints a dot if it was a success (dashboard was alive and responded).  If the dashboard does not respond, probably because of that small memory leak, then it kills it.  The Ruby server is run in a ``while :; do ...; done`` loop to restart immediately when this happens.

IRC bot
+++++++

This pane runs the actual ArchiveBot, which is an IRC bot that listens for commands about what websites to archive.

Usually, there's not much that an administrator will need to do for this.  If the bot loses its IRC connection, it will try to reconnect on its own.  This should usually work fine, but during a netsplit (a disconnect between IRC server nodes), it might reconnect to an undesired server, in which case the bot might need to be "kicked" (restarted and reconnected to the IRC server).

If you need to kick it, hit ``^C`` in this pane to kill the non-responding bot.  Then rerun the bot (by hitting the ``Up arrow key`` to show the last command), possibly after adjusting the command if needed.


plumbing
++++++++

Plumbing is responsible for much of the data flow of log lines within the control node.

The ``plumbing/updates-listener`` listens for job updates coming into Redis from the pipelines.  This produces job IDs, which are sent to ``plumbing/log-firehose``, which pulls new log lines from Redis (using the job IDs read from stdin) and pushes them to a ZeroMQ socket.  This ZeroMQ socket is used by the dashboard and the two further plumbing tools below.

The ``plumbing/analyzer`` looks at new log lines and classifies them as HTTP 1xx, 2xx, etc, or network error.

The ``plumbing/trimmer`` is an artefact of the current log flow design.  It removes old log lines, i.e. ones that have been processed by the firehose sender and the analyzer, from Redis to prevent out-of-memory errors.


cogs
++++

cogs is responsible for keeping the user agents and browser aliases in CouchDB updated and for tweeting about things getting archived.  It also prints very verbose warnings about jobs that haven't sent updates (a heartbeat) to the control node for a long time, recommending them to be 'reaped'.  These warnings may or may not be accurate.  For reaping jobs (or pipelines), see below.


Job reaping
+++++++++++

Jobs need to be reaped manually when they no longer exist but the pipeline did not inform the control node about this.  Examples include pipeline crashes (say, a freeze or a power outage).  Note that individual job crashes (e.g. due to wpull bugs) do not need to be handled on the control node; as long as the pipeline process still runs, it will treat the job as finishing once the wpull process has been killed by the pipeline operator.

If you need to reap a dead ArchiveBot job -- in this case, one with the hypothetical job id 'abcdefghiabcdefghi' -- here's what to do:

If there is no Ruby console for reaping yet:

	```bash
	cd ArchiveBot/bot
	bundle exec ruby console.rb
	```

Retrieve the job:

	```ruby
	j = Job.from_ident('abcdefghiabcdefghi', $redis)
	```

At this point, you should get a response message starting with ``<struct Job...>``.  That means the job id does exist somewhere in Redis, which is good.  Then you should run:

	```ruby
	j.fail
	```

This will kill that one job, but note that the magic Redis word in the command here is 'fail', not 'kill'.  This deletes the job state from Redis (after a few seconds).

It is possible to reap multiple jobs at once, by mapping their job id's with regex and such. Such exercises are best left to experts.

You can also clean out “nil” jobs with redis-cli in the admin console with this command:

	```bash
	idents.each { |id| $redis.del(id) }
	```

That command would send the delete command about each id to the Redis server.


Pipeline reaping
++++++++++++++++

Pipeline data is stored inside Redis. You can get a list of all the pipelines Redis knows about from the dashboard or with this command:

	```bash
	redis-cli keys pipeline:*
	```

That will list all currently assigned pipeline keys -- but some of those pipelines may be dead.

To peek at the data within any given pipeline -- in this case, a pipeline that was assigned the id 4f618cfcd81f44583a93b8bdb50470a1 -- use the command:

	```bash
	redis-cli type pipeline:4f618cfcd81f44583a93b8bdb50470a1
	```

To find out which pipelines are dead, check the web-based pipeline monitor and copy the unique key for a dead pipeline.

To reap the dead pipeline (two parts):

	```bash
	redis-cli srem pipelines pipeline:4f618cfcd81f44583a93b8bdb50470a1
	```

That removes the dead pipeline from the set of active pipelines. Then do:

	```bash
	redis-cli del pipeline:4f618cfcd81f44583a93b8bdb50470a1
	```
	***NOTE: be very careful with this; make sure you do not have the word "pipelines" in this command!***

That deletes that dead pipeline's data.


Re-sync the IRC !status command to actual Redis data
====================================================

The ArchiveBot ``!status`` command that is available in the #archivebot IRC channel on EFnet is supposed to be an accurate counter of how many jobs are currently running, aborted, completed, or pending.  But sometimes it gets un-synchronized from the actual Redis values, especially if a pipeline dies.  Here's how to automatically sync the information again, from Redis to IRC:

	```bash
	cd ArchiveBot/bot
	bundle exec ruby console.rb
	in_working = $redis.lrange('working', 0, -1); 1
	in_working.each { |ident| $redis.lrem('working', 0, ident) if Job.from_ident(ident, $redis).nil ? }
	```
