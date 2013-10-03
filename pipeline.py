import datetime
import os
import re
import string
import shutil
import redis
import time

from os import environ as env
from urlparse import urlparse
from seesaw.project import *
from seesaw.item import *
from seesaw.task import *
from seesaw.pipeline import *
from seesaw.externalprocess import *

from seesaw.util import find_executable

VERSION = "20130921.01"
USER_AGENT = "ArchiveTeam ArchiveBot/%s" % VERSION
EXPIRE_TIME = 60 * 60 * 48    # 48 hours between archive requests
WGET_LUA = find_executable('Wget+Lua', "GNU Wget 1.14.lua.20130523-9a5c",
    [ './wget-lua' ])

if not WGET_LUA:
  raise Exception("No usable Wget+Lua found.")

if 'RSYNC_URL' not in env:
  raise Exception('RSYNC_URL not set.')

if 'REDIS_URL' not in env:
  raise Exception('REDIS_URL not set.')

if 'LOG_CHANNEL' not in env:
  raise Exception('LOG_CHANNEL not set.')

RSYNC_URL = env['RSYNC_URL']
REDIS_URL = env['REDIS_URL']
LOG_CHANNEL = env['LOG_CHANNEL']

# ------------------------------------------------------------------------------

class GetItemFromQueue(Task):
  def __init__(self, redis, retry_delay=5):
    Task.__init__(self, 'GetItemFromQueue')
    self.redis = redis
    self.retry_delay = retry_delay

  def enqueue(self, item):
    self.start_item(item)
    item.log_output('Starting %s for %s' % (self, item.description()))
    self.send_request(item)

  def send_request(self, item):
    # The Python Redis client doesn't understand RPOPLPUSH yet
    ident = self.redis.execute_command('RPOPLPUSH', 'pending', 'working')
    
    if ident == None:
      self.schedule_retry(item)
    else:
      item['ident'] = ident
      item['url'] = self.redis.hget(ident, 'url')
      item.log_output('Received item %s.' % ident)
      self.complete_item(item)

  def schedule_retry(self, item):
    IOLoop.instance().add_timeout(datetime.timedelta(seconds=self.retry_delay),
      functools.partial(self.send_request, item))

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

class PreparePaths(SimpleTask):
  def __init__(self):
    SimpleTask.__init__(self, 'PreparePaths')

  def process(self, item):
    item_dir = '%s/%s' % (item['data_dir'], item['ident'])

    if os.path.isdir(item_dir):
      shutil.rmtree(item_dir)
    os.makedirs(item_dir)

    item['item_dir'] = item_dir
    item['warc_file_base'] = '%s-%s' % (item['ident'], time.strftime("%Y%m%d-%H%M%S"))
    item['source_warc_file'] = '%(item_dir)s/%(warc_file_base)s.warc.gz' % item
    item['target_warc_file'] = '%(data_dir)s/%(warc_file_base)s.warc.gz' % item
    item['cookie_jar'] = '%(item_dir)s/cookies.txt' % item

class MoveFiles(SimpleTask):
  def __init__(self):
    SimpleTask.__init__(self, "MoveFiles")

  def process(self, item):
    os.rename(item['source_warc_file'], item['target_warc_file'])
    shutil.rmtree("%(item_dir)s" % item)

class SetWarcFileSizeInRedis(SimpleTask):
  def __init__(self, redis):
    SimpleTask.__init__(self, 'SetWarcFileSizeInRedis')
    self.redis = redis

  def process(self, item):
    sz = os.stat(item['target_warc_file']).st_size
    self.redis.hset(item['ident'], 'warc_size', sz)

class MarkItemAsDone(SimpleTask):
  def __init__(self, redis, mark_done_script):
    SimpleTask.__init__(self, 'MarkItemAsDone')
    self.redis = redis
    self.mark_done = self.redis.register_script(mark_done_script)

  def process(self, item):
    archive_url = 'http://dumpground.archivingyoursh.it/%s.warc.gz' % item['warc_file_base']
    self.mark_done(keys=[item['ident']], args=[archive_url, EXPIRE_TIME,
      LOG_CHANNEL, time.time()])

# ------------------------------------------------------------------------------

redis_url = urlparse(REDIS_URL)
redis_db = int(redis_url.path[1:])
r = redis.StrictRedis(host=redis_url.hostname, port=redis_url.port, db=redis_db)

# ------------------------------------------------------------------------------

MARK_DONE = '''
local ident = KEYS[1]
local archive_url = ARGV[1]
local expire_time = ARGV[2]
local log_channel = ARGV[3]
local finished_at = ARGV[4]

redis.call('hmset', ident, 'archive_url', archive_url, 'finished_at', finished_at)
redis.call('lrem', 'working', 1, ident)
redis.call('incr', 'jobs_completed')
redis.call('expire', ident, expire_time)
redis.call('expire', ident..'_log', expire_time)
redis.call('publish', log_channel, ident)
'''

MARK_ABORTED = '''
local ident = KEYS[1]
local expire_time = ARGV[1]
local log_channel = ARGV[2]
local finished_at = ARGV[3]

redis.call('hmset', ident, 'aborted', 'true', 'finished_at', finished_at)
redis.call('incr', 'jobs_aborted')
redis.call('lrem', 'working', 1, ident)
redis.call('expire', ident, expire_time)
redis.call('expire', ident..'_log', expire_time)
redis.call('publish', log_channel, ident)
'''

LOGGER = '''
local ident = KEYS[1]
local message = ARGV[1]
local log_channel = ARGV[2]

local nextseq = redis.call('hincrby', ident, 'log_score', 1)

redis.call('zadd', ident..'_log', nextseq, message)
redis.call('publish', log_channel, ident)
'''

# ------------------------------------------------------------------------------

project = Project(
    title = "ArchiveBot request handler"
)

pipeline = Pipeline(
  GetItemFromQueue(r),
  SetFetchDepth(r),
  PreparePaths(),
  WgetDownload([WGET_LUA,
    '-U', USER_AGENT,
    '-nv',
    '-o', ItemInterpolation('%(item_dir)s/wget.log'),
    '--save-cookies', ItemInterpolation('%(cookie_jar)s'),
    '--no-check-certificate',
    '--output-document', ItemInterpolation('%(item_dir)s/wget.tmp'),
    '--truncate-output',
    '-e', 'robots=off',
    ItemInterpolation('%(recursive)s'),
    ItemInterpolation('%(level)s'),
    ItemInterpolation('%(depth)s'),
    '--page-requisites',
    '--no-parent',
    '--timeout', '60',
    '--tries', '20',
    '--waitretry', '10',
    '--warc-file', ItemInterpolation('%(item_dir)s/%(warc_file_base)s'),
    '--warc-header', 'operator: Archive Team',
    '--warc-header', 'downloaded-by: ArchiveBot',
    '--warc-header', ItemInterpolation('archivebot-job-ident: %(ident)s'),
    '--wait', '0.25',
    '--random-wait',
    '--lua-script', 'archivebot.lua',
    ItemInterpolation('%(url)s')
  ],
  accept_on_exit_code=[ 0, 1, 2, 3, 4, 5, 6, 7, 8 ],
  env={
    'ITEM_IDENT': ItemInterpolation('%(ident)s'),
    'ABORT_SCRIPT': MARK_ABORTED,
    'LOG_SCRIPT': LOGGER,
    'LOG_KEY': ItemInterpolation('%(ident)s_log'),
    'LOG_CHANNEL': LOG_CHANNEL,
    'REDIS_HOST': redis_url.hostname,
    'REDIS_PORT': str(redis_url.port),
    'REDIS_DB': str(redis_db)
  }),
  MoveFiles(),
  SetWarcFileSizeInRedis(r),
  LimitConcurrent(2,
    RsyncUpload(
      target = RSYNC_URL,
      target_source_path = ItemInterpolation("%(data_dir)s"),
      files = [
        ItemInterpolation('%(target_warc_file)s')
      ]
    )
  ),
  MarkItemAsDone(r, MARK_DONE)
)

# vim:ts=2:sw=2:et:tw=78
