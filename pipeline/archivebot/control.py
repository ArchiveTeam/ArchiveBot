import json
import os
import pykka
import redis
import time

from contextlib import contextmanager
from redis.exceptions import ConnectionError as RedisConnectionError

class ConnectionError(Exception):
    '''
    Represents connection errors that can occur when talking to the ArchiveBot
    control node, Redis or otherwise.
    '''

    pass

@contextmanager
def conn(controller):
    try:
        if not controller.connected():
            controller.connect()
        yield
    except RedisConnectionError as e:
        controller.disconnect()
        raise ConnectionError(str(e)) from e

class Control(pykka.ThreadingActor):
    '''
    Handles communication to and from the ArchiveBot control server.

    If a message cannot be processed due to a connection error, the Redis
    connection is closed and deleted.  An archivebot.control.ConnectionError
    is also raised.
    '''

    def __init__(self, redis_url, log_channel, pipeline_channel):
        super(Control, self).__init__()

        self.log_channel = log_channel
        self.pipeline_channel = pipeline_channel
        self.bytes_outstanding = 0
        self.items_downloaded_outstanding = 0
        self.items_queued_outstanding = 0
        self.redis_url = redis_url

        self.connect()

    def connected(self):
        return self.redis is not None

    def connect(self):
        if self.redis_url is None:
            raise ConnectionError('self.redis_url not set')

        self.redis = redis.StrictRedis.from_url(self.redis_url,
                decode_responses=True)

        self.register_scripts()

    def disconnect(self):
        self.redis = None

    def register_scripts(self):
        self.mark_done_script = self.redis.register_script(MARK_DONE_SCRIPT)
        self.mark_aborted_script = self.redis.register_script(MARK_ABORTED_SCRIPT)
        self.log_script = self.redis.register_script(LOGGER_SCRIPT)

    def reserve_job(self, pipeline_id, ao_only):
        candidates = [
            'pending:%s' % pipeline_id,
            'pending-ao'
        ]

        if not ao_only:
            candidates.append('pending')

        for queue in candidates:
            ident = self.dequeue_item(queue)

            if ident:
                return self.complete_reservation(ident, pipeline_id)

        return None, None

    def dequeue_item(self, queue):
        with conn(self):
            return self.redis.rpoplpush(queue, 'working')

    def complete_reservation(self, ident, pipeline_id):
        with conn(self):
            self.redis.hmset(ident, dict(
                started_at=time.time(),
                pipeline_id=pipeline_id
            ))

            return ident, self.redis.hgetall(ident)

    def heartbeat(self, ident):
        try:
            with conn(self):
                self.redis.hincrby(ident, 'heartbeat', 1)
        except ConnectionError:
            pass

    def set_warc_size(self, ident, *warc_path):
        with conn(self):
            sz = 0
            for path in warc_path:
                sz += os.stat(path).st_size
            self.redis.hset(ident, 'warc_size', sz)

    def is_aborted(self, ident):
        with conn(self):
            return self.redis.hget(ident, 'aborted')

    def mark_done(self, item, expire_time):
        with conn(self):
            self.mark_done_script(keys=[item['ident']], args=[expire_time,
                self.log_channel, int(time.time()), json.dumps(item['info']),
                item['log_key']])

    def mark_aborted(self, ident):
        with conn(self):
            self.mark_aborted_script(keys=[ident], args=[self.log_channel])

    def update_bytes_downloaded(self, ident, size):
        try:
            with conn(self):
                self.bytes_outstanding += size
                self.redis.hincrby(ident, 'bytes_downloaded',
                        self.bytes_outstanding)
                self.bytes_outstanding = 0
        except ConnectionError:
            pass

    def update_items_downloaded(self, count):
        self.items_downloaded_outstanding += count

    def update_items_queued(self, count):
        self.items_queued_outstanding += count

    def flush_item_counts(self, ident):
        try:
            with conn(self):
                self.redis.hincrby(ident, 'items_downloaded',
                        self.items_downloaded_outstanding)
                self.items_downloaded_outstanding = 0

                self.redis.hincrby(ident, 'items_queued',
                        self.items_queued_outstanding)
                self.items_queued_outstanding = 0
        except ConnectionError:
            pass

    def pipeline_report(self, pipeline_id, report):
        try:
            with conn(self):
                self.redis.hmset(pipeline_id, report)
                self.redis.sadd('pipelines', pipeline_id)
                self.redis.publish(self.pipeline_channel, pipeline_id)
        except ConnectionError:
            pass

    def unregister_pipeline(self, pipeline_id):
        try:
            with conn(self):
                self.redis.delete(pipeline_id)
                self.redis.srem('pipelines', pipeline_id)
                self.redis.publish(self.pipeline_channel, pipeline_id)
        except ConnectionError:
            pass

    def log(self, packet, ident, log_key):
        try:
            with conn(self):
                self.log_script(keys=[ident], args=[json.dumps(packet),
                    self.log_channel, log_key])
        except ConnectionError:
            pass

    def get_url_file(self, ident):
        try:
            with conn(self):
                return self.redis.hget(ident, 'url_file')
        except ConnectionError:
            pass

    def get_settings(self, ident):
        with conn(self):
            data = self.redis.hmget(ident, 'delay_min', 'delay_max',
                    'concurrency',
                    'settings_age',
                    'abort_requested',
                    'suppress_ignore_reports',
                    'ignore_patterns_set_key')

            result = dict(
                    delay_min=data[0],
                    delay_max=data[1],
                    concurrency=data[2],
                    age=data[3],
                    abort_requested=data[4],
                    suppress_ignore_reports=data[5]
                    )

            if data[6]:
                result['ignore_patterns'] = self.redis.smembers(data[6])
            else:
                result['ignore_patterns'] = []

            return result

# ------------------------------------------------------------------------------

MARK_DONE_SCRIPT = '''
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

MARK_ABORTED_SCRIPT = '''
local ident = KEYS[1]
local log_channel = ARGV[1]

redis.call('hset', ident, 'aborted', 'true')
redis.call('publish', log_channel, ident)
'''

LOGGER_SCRIPT = '''
local ident = KEYS[1]
local message = ARGV[1]
local log_channel = ARGV[2]
local log_key = ARGV[3]

local nextseq = redis.call('hincrby', ident, 'log_score', 1)

redis.call('zadd', log_key, nextseq, message)
redis.call('publish', log_channel, ident)
'''

# vim:ts=4:sw=4:et:tw=78
