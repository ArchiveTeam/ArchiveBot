import json
import redis
import time
import os
import logging
import threading

from sys import stderr
from queue import Queue, Empty
from contextlib import contextmanager
from redis.exceptions import ConnectionError as RedisConnectionError

logger = logging.getLogger('archivebot.control')

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
        self.bytes_downloaded_outstanding = 0
        self.redis_url = redis_url
        self.log_queue = Queue()

        # if ITEM_IDENT is set, we are running inside a wpull process
        self.ident = os.getenv('ITEM_IDENT')
        logger.info('Started new control process with ident={}, thread={}, this={}'.format(self.ident, threading.get_ident(), self))
        # and as such this lock will be used to manage count concurrency
        self.countslock = threading.Lock()

        self.redis = self.connect()

        self.ending = False
        self.log_thread = threading.Thread(target=self.ship_logs)

        # At some point it would be preferable to not use a daemonic thread
        # but I dare you to try and ever join it.
        self.log_thread.setDaemon(True)
        self.log_thread.start()

    def connected(self):
        return self.redis is not None

    def connect(self):
        logger.info('Attempting to connect to redis with ident={}, thread={}'.format(self.ident, threading.get_ident()))
        if self.redis_url is None:
            raise ConnectionError('self.redis_url not set')

        self.redis = redis.StrictRedis.from_url(self.redis_url,
                                                decode_responses=True)

        self.register_scripts()
        logger.info('Redis connection successful with ident={}, thread={}'.format(self.ident, threading.get_ident()))

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

    def flag_logging_thread_for_termination(self):
        logger.info('Attempting to set semaphore to close logger with id {} from thread {}'.format(log_thread.ident, threading.get_ident()))

        #self.ending = True

        logger.info('State update complete with id {} from thread {}; joining'.format(log_thread.ident, threading.get_ident()))
        # self.log_thread.join()
        logger.info('Logger thread joined to thread {}'.format(threading.get_ident()))

    def mark_done(self, item, expire_time): # used from main controller
        with conn(self):
            self.mark_done_script(keys=[item['ident']], args=[expire_time,
                self.log_channel, int(time.time()), json.dumps(item['info']),
                                                              item['log_key']])

    def mark_aborted(self, ident): # used when in wpull subprocess
        #self.flag_logging_thread_for_termination()
        with conn(self):
            self.mark_aborted_script(keys=[ident], args=[self.log_channel])

    def advise_exiting(self): # used when in wpull subprocess
        logger.info('Got exit advice with ident={}, thread={}'.format(self.ident, threading.get_ident()))
        #self.flag_logging_thread_for_termination()

    def update_bytes_downloaded(self, size):
        #logger.info('Acquiring counts lock for bytes with ident={}, thread={}'.format(self.ident, threading.get_ident()))
        with self.countslock:
            self.bytes_downloaded_outstanding += size
        #logger.info('Released counts lock for bytes with ident={}, thread={}'.format(self.ident, threading.get_ident()))

    def update_items_downloaded(self, count):
        #logger.info('Acquiring counts lock for items downloaded with ident={}, thread={}'.format(self.ident, threading.get_ident()))
        with self.countslock:
            self.items_downloaded_outstanding += count
        #logger.info('Released counts lock for items downloaded with ident={}, thread={}'.format(self.ident, threading.get_ident()))

    def update_items_queued(self, count):
        #logger.info('Acquiring counts lock for items queued with ident={}, thread={}'.format(self.ident, threading.get_ident()))
        with self.countslock:
            self.items_queued_outstanding += count
        #logger.info('Released counts lock for items queued with ident={}, thread={}'.format(self.ident, threading.get_ident()))

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

    # This function is a thread used to asynchronously ship logs to redis for
    # this job, in a daemonic thread
    def ship_logs(self):
        shipping_count = 0

        logger.info('Started log shipper thread with ident={}, thread={}'.format(self.ident, threading.get_ident()))

        with conn(self):
            with self.redis.pipeline(transaction=False) as pipe:
                #logger.info('Log shipper about to enter main loop with ident={}, thread={}'.format(self.ident, threading.get_ident()))
                while not (self.ending and self.log_queue.empty()):
                    #logger.info('Log shipper iterates main loop having ending={} and queue size={} with ident={}, thread={}'.format(self.ending, self.log_queue.qsize(), self.ident, threading.get_ident()))

                    try:
                        # Ship a log entry
                        try:
                            #logger.info('Log shipper trying to dequeue a log entry with ident={}, thread={}'.format(self.ident, threading.get_ident()))
                            entry = self.log_queue.get(timeout=5)
                            #logger.info('Log shipper got a line and trying to send with ident={}, thread={}'.format(self.ident, threading.get_ident()))
                            with conn(self):
                                    self.log_script(keys=entry['keys'], args=entry['args'], client=pipe)

                            shipping_count += 1
                            self.log_queue.task_done()
                        except Empty:
                            #logger.info('Log shipper found no logs to send with ident={}, thread={}'.format(self.ident, threading.get_ident()))
                            pass
                        except ConnectionError as exception: # If we can't ship the log entry, discard
                            #logger.info('Log shipper experienced connection error with ident={}, thread={}'.format(self.ident, threading.get_ident()))
                            self.log_queue.task_done()
                            raise exception

                        #logger.info('Log shipper sent log entry with ident={}, thread={}'.format(self.ident, threading.get_ident()))

                        # If we have accreted enough or the queue is empty, commit logs and counts
                        # The magic constant against which to compare shipping_count should be
                        # selected such that about that many log entries might be shipped every
                        # round-trip to the dashboard, under congested conditions
                        if self.log_queue.empty() or shipping_count >= 64:
                            lockcheck = False
                            with conn(self):
                                # This locking structure is necessary to avoid a deadlock that happens when
                                # redis is trying to send while another thread is trying to acquire the lock
                                #logger.info('Log shipper acquiring count lock with ident={}, thread={}'.format(self.ident, threading.get_ident()))
                                with self.countslock:
                                    #logger.info('Log shipper acquired count lock with ident={}, thread={}'.format(self.ident, threading.get_ident()))
                                    t_bytes_downloaded = self.bytes_downloaded_outstanding
                                    self.bytes_downloaded_outstanding = 0
                                    t_items_downloaded = self.items_downloaded_outstanding
                                    self.items_downloaded_outstanding = 0
                                    t_items_queued = self.items_queued_outstanding
                                    self.items_queued_outstanding = 0

                                #logger.info('Log shipper released count lock and will now ship counts with ident={}, thread={}'.format(self.ident, threading.get_ident()))

                                try:
                                    if t_bytes_downloaded > 0:
                                        #logger.info('Log shipper about to send bytes with ident={}, thread={}'.format(self.ident, threading.get_ident()))
                                        pipe.hincrby(self.ident, 'bytes_downloaded', t_bytes_downloaded)
                                    if t_items_downloaded > 0:
                                        #logger.info('Log shipper about to send items downloaded with ident={}, thread={}'.format(self.ident, threading.get_ident()))
                                        pipe.hincrby(self.ident, 'items_downloaded', t_items_downloaded)
                                    if t_items_queued > 0:
                                        #logger.info('Log shipper about to send items queued with ident={}, thread={}'.format(self.ident, threading.get_ident()))
                                        pipe.hincrby(self.ident, 'items_queued', t_items_queued)
                                    #logger.info('Log shipper done sending counts with ident={}, thread={}'.format(self.ident, threading.get_ident()))
                                except ConnectionError:
                                    pass

                                #logger.info('Log shipper about to commit entries with ident={}, thread={}'.format(self.ident, threading.get_ident()))
                                pipe.execute()
                                #logger.info('Log shipper committed entries with ident={}, thread={}'.format(self.ident, threading.get_ident()))
                           
                            shipping_count = 0

                    except ConnectionError:
                        logger.info('Log shipper got connection error while incrementing counts or committing logs with ident={}, thread={}'.format(self.ident, threading.get_ident()))

        logger.info('Log shipper exiting with ident={}, thread={}'.format(self.ident, threading.get_ident()))
        return True

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
