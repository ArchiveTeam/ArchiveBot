import datetime
import os
import shutil
import json
import argparse
import redis

from os import environ as env
from seesaw.project import *
from seesaw.item import *
from seesaw.task import *
from seesaw.pipeline import *
from seesaw.externalprocess import *

r = redis.StrictRedis(host='localhost', port=6379, db=0)

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
      item.log_output('Received item %s.' % ident)
      item['ident'] = ident
      self.complete_item(item)

  def schedule_retry(self, item):
    item.log_output('Retrying in %s seconds.' % self.retry_delay)

    IOLoop.instance().add_timeout(datetime.timedelta(seconds=self.retry_delay),
      functools.partial(self.send_request, item))

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

project = Project(
    title = "ArchiveBot request handler"
)

pipeline = Pipeline(
  GetItemFromQueue(r),
  MarkItemAsDone()
)

# vim:ts=2:sw=2:et:tw=78
