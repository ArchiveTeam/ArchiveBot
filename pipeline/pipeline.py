import os
import sys
import redis

# FIXME: This is a bit of a hack.
#
# Pipeline scripts are run with pwd set to their directory, which is why
# getcwd will (often) return the Right Thing.  A more robust solution would be
# nice, though.
sys.path.append(os.getcwd())

from archivebot import shared_config
from archivebot.seesaw import monitoring
from archivebot.seesaw import extensions
from archivebot.seesaw.tasks import *

from os import environ as env
from seesaw.project import *
from seesaw.item import *
from seesaw.task import *
from seesaw.pipeline import *
from seesaw.externalprocess import *
from seesaw.util import find_executable

if sys.version_info[0] == 2:
  from urlparse import urlparse
else:
  from urllib.parse import urlparse

VERSION = "20140322.01"
USER_AGENT = "ArchiveTeam ArchiveBot/%s" % VERSION
EXPIRE_TIME = 60 * 60 * 48  # 48 hours between archive requests
WPULL_EXE = find_executable('Wpull', '0.28',
        [ './wpull' ])

if not WPULL_EXE:
    raise Exception("No usable Wpull found.")

if 'RSYNC_URL' not in env:
    raise Exception('RSYNC_URL not set.')

if 'REDIS_URL' not in env:
    raise Exception('REDIS_URL not set.')

RSYNC_URL = env['RSYNC_URL']
REDIS_URL = env['REDIS_URL']
LOG_CHANNEL = shared_config.log_channel()
PIPELINE_CHANNEL = shared_config.pipeline_channel()

# ------------------------------------------------------------------------------
# REDIS CONNECTION
# ------------------------------------------------------------------------------

redis_url = urlparse(REDIS_URL)
redis_db = int(redis_url.path[1:])
r = redis.StrictRedis(
  host=redis_url.hostname,
  port=redis_url.port, db=redis_db,
  decode_responses=False if sys.version_info[0] == 2 else True,
)

# ------------------------------------------------------------------------------
# REDIS SCRIPTS
# ------------------------------------------------------------------------------

MARK_DONE = '''
local ident = KEYS[1]
local expire_time = ARGV[1]
local log_channel = ARGV[2]
local finished_at = ARGV[3]
local info = ARGV[4]
local log_key = ARGV[5]

redis.call('hmset', ident, 'finished_at', finished_at)
redis.call('lrem', 'working', 1, ident)

local was_aborted = redis.call('hget', ident, 'aborted')

-- If the job was aborted, we ignore the given expire time.  Instead, we set a
-- much shorter expire time -- one that's long enough for (most) subscribers
-- to read a message, but short enough to not cause undue suffering in the
-- case of retrying an aborted job.
if was_aborted then
    redis.call('incr', 'jobs_aborted')
    redis.call('expire', ident, 5)
    redis.call('expire', log_key, 5)
    redis.call('expire', ident..'_ignores', 5)
else
    redis.call('incr', 'jobs_completed')
    redis.call('expire', ident, expire_time)
    redis.call('expire', log_key, expire_time)
    redis.call('expire', ident..'_ignores', expire_time)
end

redis.call('rpush', 'finish_notifications', info)
redis.call('publish', log_channel, ident)
'''

MARK_ABORTED = '''
local ident = KEYS[1]
local log_channel = ARGV[1]

redis.call('hset', ident, 'aborted', 'true')
redis.call('publish', log_channel, ident)
'''

LOGGER = '''
local ident = KEYS[1]
local message = ARGV[1]
local log_channel = ARGV[2]
local log_key = ARGV[3]

local nextseq = redis.call('hincrby', ident, 'log_score', 1)

redis.call('zadd', log_key, nextseq, message)
redis.call('publish', log_channel, ident)
'''

# ------------------------------------------------------------------------------
# SEESAW EXTENSIONS
# ------------------------------------------------------------------------------

log_script = r.register_script(LOGGER)
extensions.install_stdout_extension(log_script, LOG_CHANNEL)

# ------------------------------------------------------------------------------
# PIPELINE
# ------------------------------------------------------------------------------

project = Project(
        title = "ArchiveBot request handler"
)

class AcceptAny:
    def __contains__(self, item):
        return True


class WpullArgs(object):
    def realize(self, item):
        args = [WPULL_EXE,
            '-U', USER_AGENT,
            '--quiet',
            '--ascii-print',
            '-o', '%(item_dir)s/wpull.log' % item,
            '--database', '%(item_dir)s/wpull.db' % item,
            '--save-cookies', '%(cookie_jar)s' % item,
            '--no-check-certificate',
            '--delete-after',
            '--no-robots',
            '--page-requisites',
            '--no-parent',
            '--timeout', '20',
            '--tries', '10',
            '--waitretry', '5',
            '--warc-file', '%(item_dir)s/%(warc_file_base)s' % item,
            '--warc-header', 'operator: Archive Team',
            '--warc-header', 'downloaded-by: ArchiveBot',
            '--warc-header', 'archivebot-job-ident: %(ident)s' % item,
            '--python-script', 'wpull_hooks.py',
            '%(url)s' % item
        ]

        self.add_args(args, ['%(recursive)s', '%(level)s', '%(depth)s'], item)

        return args

    @classmethod
    def add_args(cls, args, names, item):
        for name in names:
            value = name % item
            if value:
                args.append(value)

_, _, _, pipeline_id = monitoring.pipeline_id()

pipeline = Pipeline(
    GetItemFromQueue(r, pipeline_id),
    StartHeartbeat(r),
    SetFetchDepth(r),
    PreparePaths(),
    WriteInfo(r),
    WgetDownload(WpullArgs(),
    accept_on_exit_code=AcceptAny(),
    env={
        'ITEM_IDENT': ItemInterpolation('%(ident)s'),
        'ABORT_SCRIPT': MARK_ABORTED,
        'LOG_SCRIPT': LOGGER,
        'LOG_KEY': ItemInterpolation('%(log_key)s'),
        'REDIS_HOST': redis_url.hostname,
        'REDIS_PORT': str(redis_url.port),
        'REDIS_DB': str(redis_db),
        'PATH': os.environ['PATH']
    }),
    RelabelIfAborted(r),
    WriteInfo(r),
    MoveFiles(),
    SetWarcFileSizeInRedis(r),
    LimitConcurrent(2,
        RsyncUpload(
            target = RSYNC_URL,
            target_source_path = ItemInterpolation("%(data_dir)s"),
            files = [
                ItemInterpolation('%(target_warc_file)s'),
                ItemInterpolation('%(target_info_file)s')
            ]
        )
    ),
    StopHeartbeat(),
    MarkItemAsDone(r, EXPIRE_TIME, LOG_CHANNEL, MARK_DONE)
)

# Activate system monitoring.
monitoring.start(pipeline, r, VERSION, PIPELINE_CHANNEL)

# vim:ts=4:sw=4:et:tw=78
