=========================
ArchiveBot Administration
=========================

ArchiveBot has a central "control node" server, currently run by Archive Team member David Yip (yipdw) at ``archivebot.at.ninjawedding.org``.  This document explains how to manage it, hopefully without breaking anything.

This control node server does many things. It runs the actual bot that sits in the EFnet IRC channel #archivebot and listens to Archive Team members' commands about which websites to archive. It runs the Redis server that keeps track of all the pipelines and their data. It runs the web-based ArchiveBot dashboard and pipeline dashboard. It runs the Twitter bot that sends information about what's being archived. It has access to log files and debug information.

It also handles many manual administrative tasks that need doing from time to time, such as cleaning out (or "reaping") information about old pipelines that have gone offline, or old web crawl jobs that were aborted or died or disappeared.

Another common administrative task on this server is manually adding new pipeline operators' SSH keys so that their pipelines can communicate with the dashboard and be assigned new tasks from the queue.


Basic Information
=================

The control node server is reachable by SSH at ``archivebot.at.ninjawedding.org``.

Archive Team members can SSH into this server with two possible usernames:

	* ``archivebot@archivebot.at.ninjawedding.org`` - for performing more delicate administrative tasks
	* ``pipeline@archivebot.at.ninjawedding.org`` - for adding/editing SSH keys for new pipeline servers

Neither of these accounts has sudo access.

Long-time Archive Team volunteers used to be assigned individual user accounts on this machine, but starting in mid-2017 all new pipelines are now added to the server via the shared ``pipeline@`` account instead, with a shared ``authorized_keys`` file, to keep things simpler.

This control node server is the same server that also runs the web-based ArchiveBot dashboard:
http://dashboard.at.ninjawedding.org/

And it also runs the web-based ArchiveBot pipeline dashboard:
http://dashboard.at.ninjawedding.org/pipelines


How to add new ArchiveBot pipelines
===================================

Archive Team volunteers set up and run pipelines on their own servers. Each of these can handle several web crawls at a time, depending on their servers' individual configuration and their available hard drive space and memory.  More information and installation instructions are at GitHub:
https://github.com/ArchiveTeam/ArchiveBot/blob/master/INSTALL.pipeline

When a new pipeline is set up and all ready to go, the last step is that the server's SSH key still needs to be manually added to the control node. The new pipeline's operator should e-mail or private message one of the Archive Team members who already has SSH access to the control node server, such as David Yip (yipdw), Brooke Schreier Ganz (Asparagirl) or Just Another Archivist (JAA), who may be hanging out in #archiveteam on EFnet. One of them should SSH into the ``pipeline@archivebot.at.ninjawedding.org`` account, and do:

	```bash
	cd /home/pipeline/.ssh
	```

Then they should open the file ``authorized_keys`` with the text editor of their choice, and add the new pipeline server's SSH key to the bottom of the list, save, and quit.  If the new pipeline is set up correctly, it should then show up on the web-based pipeline dashboard shortly after that, and should start being assigned web crawl jobs from the queue.


All about tmux
==============

The control node server has many different processes running constantly. To help keep these processes running even when people log in or out, and to keep things somewhat well-organized, the server is set up with a program called ``tmux`` to run multiple "panes" of information.

When you log into the control node server, you should type ``tmux attach`` to view all the panes and easily move between them.

Here are some common tmux commands that can be helpful:

	* Control-B N - moves to the next pane
	* Control-B C - create a new pane
	* Control-B W – select a pane/window (shows all running panes)
	* Control-B [0-9] – go to a specific pane number (numbered 0 through 9)
	* Control-B S – select an entirely different tmux session (although there should usually be just one)

Each pane has a process running in it, sometimes more than one process, for handling a different administrative task.


tmux pane 0: spiped (secure pipe daemon)
++++++++++++++++++++++++++++++++++++++++

This pane runs ``spiped`` for Redis, which is used by some but not all pipelines.  ``spiped`` is secure pipe daemon, and it forwards packets from one port to another port.  The preferred connection is ssh tunneling.

Administrators probably won't need to do much in this pane, but it's useful to keep an eye on things.


tmux pane 1: pipeline manager
+++++++++++++++++++++++++++++

This pane runs the pipeline manager, which is ``plumbing/updates-listener``.  This listens for updates coming into Redis from all of the many pipelines.  It then sends these updates to a ZeroMQ socket, which is what used by the web-based ArchiveBot dashboard (and possibly a few other things?); the dashboard is listening on publicly accessible port 31337.

(This port is *not* where the ArchiveBot Twitter bot gets its data; that's a different daemon.)

Logs from this pipeline manager are stored in ``plumbing/log-firehose``.  Someday this log firehose could be replaced with Redis pubsub.


tmux pane 2: pipeline log analyzer and log trimmer
++++++++++++++++++++++++++++++++++++++++++++++++++

This pane manages the pipeline log analyzer and the pipeline log trimmer.

The log analyzer looks at updates coming off the firehose and classifies them as HTTP 1xx, 2xx, etc, or network error.

The log trimmer is an artifact of how ArchiveBot stores logs, could probably be removed someday.  It gets rid of old logs from Redis to prevent out-of-memory errors.


tmux pane 3: web-based dashboard
++++++++++++++++++++++++++++++++

This pane runs the web-based ArchiveBot dashboard, which is publicly viewable at:
http://dashboard.at.ninjawedding.org/

This tmux pane is split into two parts on the screen, top and bottom.  The top pane shows the throughput of the dashboard web socket, which is the rate of data flowing from the log firehose to the dashboard.

The web-based dashboard has a small unknown memory leak, so the bottom pane runs and monitors ivan's “dashboard killer” daemon. It constantly polls the dashboard to see if it's alive, and it prints a dot if it was a success (dashboard was alive and responded).  If the dashboard does not respond, probably because of that small memory leak, then this daemon kills it and automatically re-spawns it.


tmux pane 4: IRC bot
++++++++++++++++++++

This pane runs the actual ArchiveBot, which is an IRC bot that sits in the channel #archivebot on EFnet and listens for Archive Team volunteers feeding it commands about what websites to archive.

Usually, there's not much that an administrator will need to do for this. If the bot gets kicked off EFnet, it will try to reconnect on its own. However, EFnet sometimes has the tendency to netsplit (disconnect from some IRC nodes in a disorganized manner). If that happens, the bot might try to rejoin a server that's been split, in which case the bot might need to be "kicked" (restarted and reconnected to the IRC server).

If you need to kick it, hit ``^C`` in this pane to kill the non-responding bot. Then hit the ``Up arrow key`` to show the last command that had been typed into bash, which is usually the one that invokes the bot. You can then adjust that command if you need to (such as possibly changing the server), and then hit enter to re-run that command and reconnect the bot to EFnet.


tmux pane 5: redis-cli console
++++++++++++++++++++++++++++++

This is the console for running redis-cli commands.  It might get closed down, because it's rarely used.


tmux pane 6: job reaper and Twitter bot
+++++++++++++++++++++++++++++++++++++++

This is the job reaper, used by administrators to manually get rid of "zombie" web crawl jobs that are dead or quit but which are still showing up for some reason on the web-based dashboard, cluttering it up.

Every job has a heartbeat associated with it, which Redis monitors. This pane will let you know if certain jobs' heartbeats have not been seen for a long time, which would indicate that the jobs are zombies.

If you need to reap a dead ArchiveBot job -- in this case, one with the hypothetical job id 'abcdefghiabcdefghi' -- here's what to do in this pane:

	```bash
	cd ~/ArchiveBot/bot/
	bundle exec ruby console.rb
	j = Job.from_ident('abcdefghiabcdefghi', $redis)
	```

At this point, you should get a response message starting with ``<struct Job...>``.  That means the job id does exist somewhere in Redis, which is good. Then you should run:

	```bash
	j.fail
	```

This will kill that one job, but note that the magic Redis word in the command here is 'fail', not 'kill'.  This deletes the job state from Redis.

It is possible to reap multiple jobs at once, by mapping their job id's with regex and such. Such exercises are best left to experts.

You can also clean out “nil” jobs with redis-cli in the admin console with this command:

	```bash
	idents.each { |id| $redis.del(id) }
	```

That command would send the delete command about each id to the Redis server.

This tmux pane 6 *also* runs the ArchiveBot Twitter bot connector. You shouldn't need to do anything with that most of the time, but it ever dies, go to pane 6 and press up and enter to re-run command, which is:

	```bash
	bundle exec ruby start.rb -t twitter_archivebot.json
	```

The Twitter bot is publicly viewable at https://twitter.com/ArchiveBot/ .


tmux pane 7: couchdb
++++++++++++++++++++

This pane inserts couchdb documents.  You can probably ignore this, and should leave it as-is.


tmux pane 8: the pipeline reaper
++++++++++++++++++++++++++++++++

This is the pane where you can reap old dead pipelines from the pipeline monitor.  You can view the web-based pipeline monitor page here: http://dashboard.at.ninjawedding.org/pipelines

Pipeline data is stored inside Redis. You can get a list of all the pipelines Redis knows about with this command:

	```bash
	~/redis-2.8.6/src/redis-cli keys pipeline:*
	```

That will list all currently assigned pipeline keys -- but some of those pipelines may be dead.

To peek at the data within any given pipeline -- in this case, a pipeline that was assigned the id 4f618cfcd81f44583a93b8bdb50470a1 -- use the command:

	```bash
	~/redis-2.8.6/src/redis-cli type pipeline:4f618cfcd81f44583a93b8bdb50470a1
	```

To find out which pipelines are dead, check the web-based pipeline monitor and copy the unique key for a dead pipeline.

To reap the dead pipeline (two parts):

	```bash
	~/redis-2.8.6/src/redis-cli srem pipelines pipeline:4f618cfcd81f44583a93b8bdb50470a1
	```

That removes the dead pipeline from the set of active pipelines. Then do:

	```bash
	~/redis-2.8.6/src/redis-cli del pipeline:4f618cfcd81f44583a93b8bdb50470a1
	```
	***NOTE: be very careful with this; make sure you do not have the word "pipelines" in this command!***

That deletes that dead pipeline's data.


Re-sync the IRC !status command to actual Redis data
====================================================

The ArchiveBot ``!status`` command that is available in the #archivebot IRC channel on EFnet is supposed to be an accurate counter of how many jobs are currently running, aborted, completed, or pending.  But sometimes it gets un-synchronized from the actual Redis values, especially if a pipeline dies.  Here's how to automatically sync the information again, from Redis to IRC:

	```bash
	cd /ArchiveBot/bot
	bundle exec ruby console.rb
	in_working = $redis.lrange('working', 0, -1); 1
	in_working.each { |ident| $redis.lrem('working', 0, ident) if Job.from_ident(ident, $redis).nil ? }
	```

