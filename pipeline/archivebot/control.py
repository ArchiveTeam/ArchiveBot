import json
import redis
import time

from queue import Queue, Empty
from threading import Thread
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

def candidate_queues(named_queues, pipeline_nick, ao_only):
    '''
    Generates names of queues that this pipeline will check for work.
    '''

    def applies(q):
        return q.replace('pending:', '') in pipeline_nick

    if ao_only:
        return ['pending-ao']
    else:
        matches = [q for q in named_queues if applies(q)]
        matches.append('pending-ao')
        matches.append('pending')

        return matches

class Control(object):
    '''
    Handles communication to and from the ArchiveBot control server.

    If a message cannot be processed due to a connection error, the Redis
    connection is closed and deleted.  An archivebot.control.ConnectionError
    is also raised.
    '''

    def __init__(self, redis_url, log_channel, pipeline_channel):
        self.log_channel = log_channel
        self.pipeline_channel = pipeline_channel
        self.items_downloaded_outstanding = 0
        self.items_queued_outstanding = 0
        self.redis_url = redis_url
        self.log_queue = Queue()
        self.bytes_downloaded_queue = Queue()
        self.item_count_queue = Queue()

        self.connect()

        #log_thread is joined in finish_logging()
        self.ending = False
        self.log_thread = Thread(target=self.ship_logs)
        self.log_thread.start()

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

    def all_named_pending_queues(self):
        with conn(self):
            pipelines = set()

            for name in self.redis.scan_iter('pending:*'):
                pipelines.add(name)

            return pipelines

    def reserve_job(self, pipeline_id, pipeline_nick, ao_only):
        named_queues = self.all_named_pending_queues()

        for queue in candidate_queues(named_queues, pipeline_nick, ao_only):
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
        self.bytes_downloaded_queue.put({'ident': ident,
                                         'bytes': size
                                        })

    def update_items_downloaded(self, count):
        self.items_downloaded_outstanding += count

    def update_items_queued(self, count):
        self.items_queued_outstanding += count

    def flush_item_counts(self, ident):
        self.item_count_queue.put({'ident': ident,
                                   'items_downloaded':
                                       self.items_downloaded_outstanding,
                                   'items_queued': self.items_queued_outstanding
                                  })
        self.items_downloaded_outstanding = 0
        self.items_queued_outstanding = 0

    def pipeline_report(self, pipeline_id, report):
        try:
            with conn(self):
                self.redis.hmset(pipeline_id, report)
                self.redis.sadd('pipelines', pipeline_id)
                self.redis.publish(self.pipeline_channel, pipeline_id)
        except ConnectionError:
            pass

    def finish_logging(self):
        self.ending = True
        self.log_thread.join()

    def unregister_pipeline(self, pipeline_id):
        try:
            with conn(self):
                self.redis.delete(pipeline_id)
                self.redis.srem('pipelines', pipeline_id)
                self.redis.publish(self.pipeline_channel, pipeline_id)
        except ConnectionError:
            pass

    # This function is a thread used to asynchronously ship logs to redis for
    # this job, in a daemonic thread
    def ship_logs(self):
        bytes_entries = {}
        counts_entries = {}
        shipping_count = 0

        with self.redis.pipeline(transaction=False) as pipe:
            while not (self.ending and
                       self.log_queue.empty() and
                       self.bytes_downloaded_queue.empty() and
                       self.item_count_queue.empty()):
                try:
                    # Ship a log entry
                    try:
                        entry = self.log_queue.get(timeout=5)
                        with conn(self):
                            self.log_script(keys=entry['keys'], args=entry['args'], client=pipe)
                        self.log_queue.task_done()
                    except Empty:
                        pass
                    except ConnectionError as exception: # If we can't ship the log entry, discard
                        self.log_queue.task_done()
                        raise exception

                    # Aggregate counts to ship when logs do
                    try:
                        entry = self.bytes_downloaded_queue.get(block=False)
                        if entry['ident'] in bytes_entries:
                            bytes_entries[entry['ident']] += int(entry['bytes'])
                        else:
                            bytes_entries[entry['ident']] = int(entry['bytes'])
                        self.bytes_downloaded_queue.task_done()
                    except Empty:
                        pass

                    try:
                        entry = self.item_count_queue.get(block=False)
                        if entry['ident'] in counts_entries:
                            counts_entries[entry['ident']][0] += int(entry['items_downloaded'])
                            counts_entries[entry['ident']][1] += int(entry['items_queued'])
                        else:
                            counts_entries[entry['ident']] = [
                                int(entry['items_downloaded']),
                                int(entry['items_queued'])
                            ]
                        self.item_count_queue.task_done()
                    except Empty:
                        pass

                    # If we have accreted enough or the queue is empty, commit logs and counts
                    # The magic constant against which to compare shipping_count should be
                    # selected such that about that many log entries might be shipped every
                    # round-trip to the dashboard, under congested conditions
                    if self.log_queue.empty() or shipping_count >= 64:
                        for ident, count in bytes_entries.iteritems():
                            pipe.hincrby(ident, 'bytes_downloaded', count)
                            bytes_entries = {}

                        for ident, data in counts_entries.iteritems():
                            pipe.hincrby(ident, 'items_downloaded', data[0])
                            pipe.hincrby(ident, 'items_queued', data[1])
                            counts_entries = {}

                        pipe.execute()
                        shipping_count = 0

                except ConnectionError:
                    pass

    def log(self, packet, ident, log_key):
        self.log_queue.put({'keys': [ident],
                            'args': [json.dumps(packet), self.log_channel, log_key]
                           })

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
