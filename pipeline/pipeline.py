import atexit
import datetime
import hashlib
import os
import re
import psutil
import socket
import string
import shutil
import sys
import redis
import time
import json

# FIXME: This is a bit of a hack.
#
# Pipeline scripts are run with pwd set to their directory, which is why
# getcwd will (often) return the Right Thing.  A more robust solution would be
# nice, though.
sys.path.append(os.getcwd())
import shared_config

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

VERSION = "20140321.01"
USER_AGENT = "ArchiveTeam ArchiveBot/%s" % VERSION
EXPIRE_TIME = 60 * 60 * 48  # 48 hours between archive requests
WPULL_EXE = find_executable('Wpull', '0.26',
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
# SYSTEM MONITORING
# ------------------------------------------------------------------------------

hostname = socket.gethostname()
fqdn = socket.getfqdn()
pid = os.getpid()

pipeline_id_input = "%s:%s:%s" % (hostname, fqdn, pid)
m = hashlib.md5()
m.update(pipeline_id_input.encode('ascii'))
pipeline_id = 'pipeline:%s' % m.hexdigest()

def do_report(pipeline, redis):
    process_report = {
        'id': pipeline_id,
        'hostname': hostname,
        'fqdn': fqdn,
        'pid': pid,
        'version': VERSION,
        'mem_usage': psutil.virtual_memory().percent,
        'disk_usage': psutil.disk_usage(pipeline.data_dir).percent,
        'ts': int(time.time())
    }

    redis.hmset(pipeline_id, process_report)
    redis.sadd('pipelines', pipeline_id)
    redis.publish(PIPELINE_CHANNEL, pipeline_id)

def unregister_pipeline():
    r.delete(pipeline_id)
    r.srem('pipelines', pipeline_id)
    r.publish(PIPELINE_CHANNEL, pipeline_id)

# ------------------------------------------------------------------------------
# TASKS
# ------------------------------------------------------------------------------

class GetItemFromQueue(Task):
    def __init__(self, redis, pipeline_id, retry_delay=5):
        Task.__init__(self, 'GetItemFromQueue')
        self.redis = redis
        self.pipeline_id = pipeline_id
        self.retry_delay = retry_delay
        self.pipeline_queue = 'pending:%s' % self.pipeline_id

    def enqueue(self, item):
        self.start_item(item)
        item.log_output('Starting %s for %s' % (self, item.description()))
        self.send_request(item)

    def send_request(self, item):
        ident = self.get_item(item)

        if ident == None:
            self.schedule_retry(item)
        else:
            pipeline_attrs = {
                'started_at': int(time.time()),
                'pipeline_id': self.pipeline_id
            }

            self.redis.hmset(ident, pipeline_attrs)

            data = self.redis.hmget(ident, 'url', 'slug', 'log_key')

            item['ident'] = ident
            item['url'] = data[0]
            item['slug'] = data[1]
            item['log_key'] = data[2]
            item.log_output('Received item %s.' % ident)
            self.complete_item(item)

    def get_item(self, item):
        item.may_be_canceled = False
        ident = self.redis.rpoplpush(self.pipeline_queue, 'working')

        if ident == None:
            return self.redis.rpoplpush('pending', 'working')
        else:
            return ident

    def schedule_retry(self, item):
        item.may_be_canceled = True

        IOLoop.instance().add_timeout(datetime.timedelta(seconds=self.retry_delay),
            functools.partial(self.send_request, item))

class StartHeartbeat(SimpleTask):
    def __init__(self, redis):
        SimpleTask.__init__(self, 'StartHeartbeat')
        self.redis = redis

    def process(self, item):
        cb = tornado.ioloop.PeriodicCallback(
                functools.partial(self.send_heartbeat, item),
                1000)

        item['heartbeat'] = cb

        cb.start()

    def send_heartbeat(self, item):
        self.redis.hincrby(item['ident'], 'heartbeat', 1)

class SetFetchDepth(SimpleTask):
    def __init__(self, redis):
        SimpleTask.__init__(self, 'SetFetchDepth')
        self.redis = redis

    def process(self, item):
        depth = self.redis.hget(item['ident'], 'fetch_depth')

        # Unfortunately, depth zero means the same thing as infinite depth to
        # wget, so we need to special-case it
        if depth == 'shallow':
            item['recursive'] = ''
            item['level'] = ''
            item['depth'] = ''
        else:
            item['recursive'] = '--recursive'
            item['level'] = '--level'
            item['depth'] = depth

class TargetPathMixin(object):
    def set_target_paths(self, item):
        item['target_warc_file'] = '%(data_dir)s/%(warc_file_base)s.warc.gz' % item
        item['target_info_file'] = '%(data_dir)s/%(warc_file_base)s.json' % item

class PreparePaths(SimpleTask, TargetPathMixin):
    def __init__(self):
        SimpleTask.__init__(self, 'PreparePaths')

    def process(self, item):
        item_dir = '%(data_dir)s/%(ident)s' % item
        last_five = item['ident'][0:5]

        if os.path.isdir(item_dir):
            shutil.rmtree(item_dir)
        os.makedirs(item_dir)

        item['item_dir'] = item_dir
        item['warc_file_base'] = '%s-%s-%s' % (item['slug'],
                time.strftime("%Y%m%d-%H%M%S"), last_five)
        item['source_warc_file'] = '%(item_dir)s/%(warc_file_base)s.warc.gz' % item
        item['source_info_file'] = '%(item_dir)s/%(warc_file_base)s.json' % item
        item['cookie_jar'] = '%(item_dir)s/cookies.txt' % item

        self.set_target_paths(item)

class MoveFiles(SimpleTask):
    def __init__(self):
        SimpleTask.__init__(self, "MoveFiles")

    def process(self, item):
        os.rename(item['source_warc_file'], item['target_warc_file'])
        os.rename(item['source_info_file'], item['target_info_file'])
        shutil.rmtree("%(item_dir)s" % item)

class RelabelIfAborted(SimpleTask, TargetPathMixin):
    def __init__(self, redis):
        SimpleTask.__init__(self, 'RelabelIfAborted')
        self.redis = redis

    def process(self, item):
        if self.redis.hget(item['ident'], 'aborted'):
            item['warc_file_base'] = '%(warc_file_base)s-aborted' % item

            self.set_target_paths(item)

            item.log_output('Adjusted target WARC path to %(target_warc_file)s' %
                    item)

class WriteInfo(SimpleTask):
    def __init__(self, redis):
        SimpleTask.__init__(self, 'WriteInfo')
        self.redis = redis

    def process(self, item):
        job_data = self.redis.hgetall(item['ident'])

        # The "aborted" key might not have been written by any prior process,
        # i.e. if the job wasn't aborted.  For accessor convenience, we add
        # that key here.
        if 'aborted' in job_data:
            aborted = job_data['aborted']
        else:
            aborted = False

        # This JSON object's fieldset is an externally visible interface.
        # Adding fields is fine; changing existing ones, not so much.
        item['info'] = {
                'url': job_data['url'],
                'aborted': aborted,
                'fetch_depth': job_data['fetch_depth'],
                'queued_at': job_data['queued_at'],
                'started_in': job_data['started_in'],
                'started_by': job_data['started_by'],
                'pipeline_id': job_data['pipeline_id']
        }

        with open(item['source_info_file'], 'w') as f:
            f.write(json.dumps(item['info'], indent=True))

class SetWarcFileSizeInRedis(SimpleTask):
    def __init__(self, redis):
        SimpleTask.__init__(self, 'SetWarcFileSizeInRedis')
        self.redis = redis

    def process(self, item):
        sz = os.stat(item['target_warc_file']).st_size
        self.redis.hset(item['ident'], 'warc_size', sz)

class StopHeartbeat(SimpleTask):
    def __init__(self):
        SimpleTask.__init__(self, 'StopHeartbeat')

    def process(self, item):
        if 'heartbeat' in item:
            item['heartbeat'].stop()
            del item['heartbeat']
        else:
            item.log_output("Warning: couldn't find a heartbeat to stop")

class MarkItemAsDone(SimpleTask):
    def __init__(self, redis, mark_done_script):
        SimpleTask.__init__(self, 'MarkItemAsDone')
        self.redis = redis
        self.mark_done = self.redis.register_script(mark_done_script)

    def process(self, item):
        self.mark_done(keys=[item['ident']], args=[EXPIRE_TIME, LOG_CHANNEL,
            int(time.time()), json.dumps(item['info']), item['log_key']])

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

# Each item has a log output.  We want to be able to broadcast that in the
# ArchiveBot Dashboard; therefore, we tee the item log output to Redis.
old_logger = Item.log_output
log_script = r.register_script(LOGGER)

def tee_to_redis(self, data, full_line=True):
    old_logger(self, data, full_line)

    if 'ident' in self and 'log_key' in self:
        packet = {
            'type': 'stdout',
            'ts': int(time.time()),
            'message': data
        }

        log_script(keys=[self['ident']], args=[json.dumps(packet),
            LOG_CHANNEL, self['log_key']])

Item.log_output = tee_to_redis

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
            '--python-script', 'archivebot.py',
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
    MarkItemAsDone(r, MARK_DONE)
)

# Activate system monitoring.

atexit.register(unregister_pipeline)

cb = tornado.ioloop.PeriodicCallback(
        functools.partial(do_report, pipeline, r),
        1000)

cb.start()

# vim:ts=4:sw=4:et:tw=78
