import datetime
import functools
import json
import os
import shutil
import time
import tornado.ioloop

from seesaw.task import Task, SimpleTask
from tornado.ioloop import IOLoop

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
        ident = self.get_item()

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

    def get_item(self):
        ident = self.redis.rpoplpush(self.pipeline_queue, 'working')

        if ident == None:
            return self.redis.rpoplpush('pending', 'working')
        else:
            return ident

    def schedule_retry(self, item):
        item.may_be_canceled = True

        def retry():
            item.may_be_canceled = False
            self.send_request(item)

        IOLoop.instance().add_timeout(datetime.timedelta(seconds=self.retry_delay),
                retry)

# ------------------------------------------------------------------------------

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

# ------------------------------------------------------------------------------

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

# ------------------------------------------------------------------------------

class TargetPathMixin(object):
    def set_target_paths(self, item):
        item['target_warc_file'] = '%(data_dir)s/%(warc_file_base)s.warc.gz' % item
        item['target_info_file'] = '%(data_dir)s/%(warc_file_base)s.json' % item

# ------------------------------------------------------------------------------

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

# ------------------------------------------------------------------------------

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

# ------------------------------------------------------------------------------

class MoveFiles(SimpleTask):
    def __init__(self):
        SimpleTask.__init__(self, "MoveFiles")

    def process(self, item):
        os.rename(item['source_warc_file'], item['target_warc_file'])
        os.rename(item['source_info_file'], item['target_info_file'])
        shutil.rmtree("%(item_dir)s" % item)

# ------------------------------------------------------------------------------

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

# ------------------------------------------------------------------------------

class SetWarcFileSizeInRedis(SimpleTask):
    def __init__(self, redis):
        SimpleTask.__init__(self, 'SetWarcFileSizeInRedis')
        self.redis = redis

    def process(self, item):
        sz = os.stat(item['target_warc_file']).st_size
        self.redis.hset(item['ident'], 'warc_size', sz)

# ------------------------------------------------------------------------------

class StopHeartbeat(SimpleTask):
    def __init__(self):
        SimpleTask.__init__(self, 'StopHeartbeat')

    def process(self, item):
        if 'heartbeat' in item:
            item['heartbeat'].stop()
            del item['heartbeat']
        else:
            item.log_output("Warning: couldn't find a heartbeat to stop")

# ------------------------------------------------------------------------------

class MarkItemAsDone(SimpleTask):
    def __init__(self, redis, expire_time, log_channel, mark_done_script):
        SimpleTask.__init__(self, 'MarkItemAsDone')
        self.redis = redis
        self.expire_time = expire_time
        self.log_channel = log_channel
        self.mark_done = self.redis.register_script(mark_done_script)

    def process(self, item):
        self.mark_done(keys=[item['ident']], args=[self.expire_time,
            self.log_channel, int(time.time()), json.dumps(item['info']),
            item['log_key']])


# vim:ts=4:sw=4:et:tw=78
