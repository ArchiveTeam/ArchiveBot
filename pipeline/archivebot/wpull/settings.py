import os
import re
import redis
import threading
import time

from .ignoracle import Ignoracle, parameterize_record_info
from .. import shared_config
from ..control import ConnectionError
from redis.exceptions import ConnectionError as RedisConnectionError

class Settings(object):
    '''
    Synchronizes access to job settings.
    '''

    settings_lock = threading.RLock()
    ignoracle = Ignoracle()

    settings = dict(
            age=None,
            concurrency=None,
            abort_requested=None,
            delay_min=None,
            delay_max=None,
            suppress_ignore_reports=False
    )

    def update_settings(self, new_settings):
        '''
        Replaces existing settings with new data.
        '''
        with self.settings_lock:
            self.settings['delay_min'] = int_or_none(new_settings['delay_min'])
            self.settings['delay_max'] = int_or_none(new_settings['delay_max'])
            self.settings['age'] = int_or_none(new_settings['age'])
            self.settings['concurrency'] = int_or_none(new_settings['concurrency'])
            self.settings['abort_requested'] = new_settings['abort_requested']
            self.settings['suppress_ignore_reports'] = new_settings['suppress_ignore_reports']

            self.ignoracle.set_patterns(new_settings['ignore_patterns'])

    def age(self):
        with self.settings_lock:
            return self.settings['age'] or 0

    def ignore_url_p(self, url, record_info):
        '''
        Returns whether a URL should be ignored.
        '''
        parameters = parameterize_record_info(record_info)

        return self.ignoracle.ignores(url, **parameters)

    def abort_requested(self):
        '''
        Returns True if job abort was requested, False otherwise.
        '''

        with self.settings_lock:
            return self.settings['abort_requested']

    def delay_time_range(self):
        '''
        Returns a range of valid sleep times.  Sleep times are in milliseconds.
        '''

        with self.settings_lock:
            return self.settings['delay_min'] or 0, self.settings['delay_max'] or 0

    def concurrency(self):
        '''
        Number of wpull fetchers to run.
        '''

        with self.settings_lock:
            return self.settings['concurrency'] or 1

    def suppress_ignore_reports(self):
        '''
        Whether ignore reports should be suppressed.
        '''

        with self.settings_lock:
            return self.settings['suppress_ignore_reports']

    def inspect(self):
        '''
        Returns a string describing the current settings.
        '''
        with self.settings_lock:
            iglen = len(self.ignoracle.patterns)
            sl, sm = self.delay_time_range()
        
            report = str(self.concurrency()) + ' workers, '
            report += str(iglen) + ' ignores, '
            report += 'delay min/max: [' + str(sl) + ', ' + str(sm) + '] ms, '

            if self.settings['suppress_ignore_reports']:
                report += 'suppressing ignore reports'
            else:
                report += 'showing ignore reports'

            return report

# ---------------------------------------------------------------------------

class Listener(object):
    '''
    Listens for changes to job settings.  When changes are detected, retrieves
    job settings and updates the pipeline's settings copy.
    '''

    def __init__(self, redis_url, settings, control, ident):
        self.redis_url = redis_url
        self.settings = settings
        self.control = control
        self.ident = ident
        self.thread = None

    def start(self):
        '''
        Starts listening for settings changes.
        '''

        # Stop any existing listener.
        self.stop()

        self.thread = ListenerWorkerThread(self.redis_url, self.settings,
                self.control, self.ident)
        self.thread.start()

    def check(self):
        '''
        Checks whether the worker thread is alive.  If it isn't, nils out
        references to the existing object and starts a new instance.

        This should be called from a loop.
        '''

        if self.thread and not self.thread.is_alive():
            print('Settings listener died; restarting.')
            self.thread = None
            self.start()

    def stop(self):
        if self.thread:
            self.thread.stop()
            self.thread.join()

class ListenerWorkerThread(threading.Thread):
    '''
    Runs two jobs:

    1.  Subscribes to the job's update pubsub channel and pulls new
        settings when an appropriate message is received.
    2.  Every 30 seconds, unconditionally updates job settings.

    The latter bit is done to ensure that we eventually receive the latest
    job settings, even if we miss a pubsub update.
    '''

    def __init__(self, redis_url, settings, control, ident):
        super(ListenerWorkerThread, self).__init__()

        self.redis_url = redis_url
        self.settings = settings
        self.control = control
        self.job_ident = ident
        self.running = True
        self.reconnect_timeout = 5.0

    def stop(self):
        self.running = False

    def run(self):
        while self.running:
            try:
                self.update_settings()
                self.last_run = time.monotonic()

                r = redis.StrictRedis.from_url(self.redis_url)
                p = r.pubsub()
                p.subscribe(shared_config.job_channel(self.job_ident))

                print('Settings listener connected.')

                while self.running:
                    self.process_messages(p)
                    self.run_update_check()
                    time.sleep(0.1)

                p.close()

            # We catch both RedisConnectionError and ConnectionError because
            # the former may be raised directly from pubsub.
            except (RedisConnectionError, ConnectionError) as e:
                print('Settings listener disconnected (cause: %s).  Reconnecting in %s seconds.' % (str(e), self.reconnect_timeout))
                r = None
                p = None
                time.sleep(self.reconnect_timeout)

    def process_messages(self, p):
        msg = p.get_message(ignore_subscribe_messages=True)

        if msg:
            old_age = self.settings.age()
            new_age = int(msg['data'])

            if old_age < new_age:
                self.update_settings()

    def run_update_check(self):
        now = time.monotonic()

        if now - self.last_run > 30:
            self.update_settings()
            self.last_run = now

    def update_settings(self):
        new_settings = self.control.get_settings(self.job_ident)

        self.settings.update_settings(new_settings)

# ---------------------------------------------------------------------------

def int_or_none(v):
    if v:
        return int(v)
    else:
        return None

# vim:ts=4:sw=4:et:tw=78
