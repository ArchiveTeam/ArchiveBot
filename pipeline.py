import datetime
import os
import re
import string
import shutil
import redis

from os import environ as env
from urlparse import urlparse
from seesaw.project import *
from seesaw.item import *
from seesaw.task import *
from seesaw.pipeline import *
from seesaw.externalprocess import *

from seesaw.util import find_executable

VERSION = "20130917.01"
USER_AGENT = "ArchiveTeam ArchiveBot/%s" % VERSION
WGET_LUA = find_executable('Wget+Lua', "GNU Wget 1.14.lua.20130523-9a5c",
    [ './wget-lua' ])

if not WGET_LUA:
  raise Exception("No usable Wget+Lua found.")

if 'RSYNC_URL' not in env:
  raise Exception('RSYNC_URL not set.')

RSYNC_URL = env['RSYNC_URL']

# ------------------------------------------------------------------------------

class GetItemFromQueue(Task):
  def __init__(self, redis, retry_delay=30):
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
      item.log_output('No item received.')
      self.schedule_retry(item)
    else:
      item['ident'] = ident
      item['url'] = self.redis.hget(ident, 'url')
      item.log_output('Received item %s.' % ident)
      self.complete_item(item)

  def schedule_retry(self, item):
    item.log_output('Retrying in %s seconds.' % self.retry_delay)

    IOLoop.instance().add_timeout(datetime.timedelta(seconds=self.retry_delay),
      functools.partial(self.send_request, item))

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
    item['cookie_jar'] = '%(item_dir)s/cookies.txt' % item


class PrepareDomains(SimpleTask):
  '''
  Many websites accept (and provide) links at both https?://www.example.com
  and https?://example.com.  We should follow both if both are provided and if
  they go to the same location.

  Unfortunately, it's really, really hard to determine whether or not
  example.com will put you at the same place as www.example.com.  You can't
  look at IPs and you can't use CNAMEs.

  The easiest way to do this is heuristically:

  if given www.example.com
      add example.com to follow list
  if given example.com
      add www.example.com to follow list
  else
      keep follow list as is
  '''
  def __init__(self):
    SimpleTask.__init__(self, 'PrepareDomains')

    self.dub_regex = re.compile('^www\.*')
    self.bare_regex = re.compile('^[^.]+\.[^.]+$')

  def process(self, item):
    res = urlparse(item['url'])
    domains = []

    domains.append(res.hostname)

    if self.dub_regex.match(res.hostname):
      domains.append(string.replace(res.hostname, 'www.', ''))
    elif self.bare_regex.match(res.hostname):
      domains.append('www.%s' % res.hostname)

    item['domains'] = ','.join(domains)

class MoveFiles(SimpleTask):
  def __init__(self):
    SimpleTask.__init__(self, "MoveFiles")

  def process(self, item):
    os.rename("%(item_dir)s/%(warc_file_base)s.warc.gz" % item,
              "%(data_dir)s/%(warc_file_base)s.warc.gz" % item)

    shutil.rmtree("%(item_dir)s" % item)

class MarkItemAsDone(SimpleTask):
  def __init__(self, redis):
    SimpleTask.__init__(self, 'MarkItemAsDone')
    self.redis = redis

  def process(self, item):
    pipe = self.redis.pipeline()

    pipe.hset(item['ident'], 'archive_url', 'foobar')
    pipe.lrem('working', 1, item['ident'])
    pipe.incr('jobs_completed')
    pipe.execute()

# ------------------------------------------------------------------------------

r = redis.StrictRedis(host='localhost', port=6379, db=0)

project = Project(
    title = "ArchiveBot request handler"
)

pipeline = Pipeline(
  GetItemFromQueue(r),
  PreparePaths(),
  PrepareDomains(),
  WgetDownload([WGET_LUA,
    '-U', USER_AGENT,
    '-nv',
    '-o', ItemInterpolation('%(item_dir)s/wget.log'),
    '--save-cookies', ItemInterpolation('%(cookie_jar)s'),
    '--no-check-certificate',
    '--output-document', ItemInterpolation('%(item_dir)s/wget.tmp'),
    '--truncate-output',
    '-e', 'robots=off',
    '--recursive', '--level=inf',
    '--page-requisites',
    '--no-parent',
    '--timeout', '60',
    '--tries', '20',
    '--waitretry', '10',
    '--domains', ItemInterpolation('%(domains)s'),
    '--span-hosts',
    '--warc-file', ItemInterpolation('%(item_dir)s/%(warc_file_base)s'),
    '--warc-header', 'operator: Archive Team',
    '--warc-header', 'downloaded-by: ArchiveBot',
    '--warc-header', ItemInterpolation('archivebot-job-ident: %(ident)s'),
    ItemInterpolation('%(url)s')
  ],
  accept_on_exit_code=[ 0, 4, 6, 8 ]),
  MoveFiles(),
  LimitConcurrent(2,
    RsyncUpload(
      target = RSYNC_URL,
      target_source_path = ItemInterpolation("%(data_dir)s"),
      files = [
        ItemInterpolation('%(data_dir)s/%(warc_file_base)s.warc.gz')
      ]
    )
  ),
  MarkItemAsDone(r)
)

# vim:ts=2:sw=2:et:tw=78
