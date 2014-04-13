import os
import pykka
import re
import redis
import threading
import time

from .. import pattern_conversion
from .. import shared_config
from ..control import ConnectionError
from redis.exceptions import ConnectionError as RedisConnectionError

class Settings(pykka.ThreadingActor):
    '''
    Synchronizes access to job settings.
    '''

    settings = dict(
            age=None,
            concurrency=None,
            abort_requested=None,
            ignore_patterns={},
            delay_min=None,
            delay_max=None,
            pagereq_delay_min=None,
            pagereq_delay_max=None
    )

    def update_settings(self, new_settings):
        '''
        Replaces existing settings with new data.
        '''
        self.settings['delay_min'] = int_or_none(new_settings['delay_min'])
        self.settings['delay_max'] = int_or_none(new_settings['delay_max'])
        self.settings['pagereq_delay_min'] = int_or_none(new_settings['pagereq_delay_min'])
        self.settings['pagereq_delay_max'] = int_or_none(new_settings['pagereq_delay_max'])
        self.settings['ignore_patterns'] = build_patterns(new_settings['ignore_patterns'])
        self.settings['age'] = int_or_none(new_settings['age'])
        self.settings['concurrency'] = int_or_none(new_settings['concurrency'])
        self.settings['abort_requested'] = new_settings['abort_requested']

    def age(self):
        return self.settings['age'] or 0

    def ignore_url_p(self, url):
        '''
        If a URL matches an ignore pattern, returns the matching pattern.
        Otherwise, returns false.
        '''

        for pattern in self.settings['ignore_patterns']:
            try:
                match = pattern.search(url)
            except re.error as error:
                # XXX: We might not want to ignore this error
                print('Regular expression error:' + str(error) + ' on ' + pattern)
                return False
    
            if match:
                return pattern
    
        return False

    def abort_requested(self):
        '''
        Returns True if job abort was requested, False otherwise.
        '''

        return self.settings['abort_requested']

    def delay_time_range(self):
        '''
        Returns a range of valid sleep times.  Sleep times are in milliseconds.
        '''

        return self.settings['delay_min'] or 0, self.settings['delay_max'] or 0

    def pagereq_delay_time_range(self):
        '''
        Returns a range of valid sleep times for page requisites.  Sleep times
        are in milliseconds.
        '''

        return self.settings['pagereq_delay_min'] or 0, self.settings['pagereq_delay_max'] or 0

    def concurrency(self):
        '''
        Number of wpull fetchers to run.
        '''

        return self.settings['concurrency'] or 1

    def inspect(self):
        '''
        Returns a string describing the current settings.
        '''

        iglen = len(self.settings['ignore_patterns'])
        sl, sm = self.delay_time_range()
        rsl, rsm = self.pagereq_delay_time_range()
        
        report = str(self.concurrency()) + ' workers, '
        report += str(iglen) + ' ignores, '
        report += 'delay min/max: [' + str(sl) + ', ' + str(sm) + '] ms, '
        report += 'pagereq delay min/max: [' + str(rsl) + ', ' + str(rsm) + '] ms'
        
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
        super(ListenerWorkerThread, self).__init__(daemon=True)

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
            old_age = self.settings.age().get()
            new_age = int(msg['data'])

            if old_age < new_age:
                self.update_settings()

    def run_update_check(self):
        now = time.monotonic()

        if self.last_run - now > 30:
            self.update_settings()
            self.last_run = now

    def update_settings(self):
        new_settings = self.control.get_settings(self.job_ident).get()

        self.settings.update_settings(new_settings)

# ---------------------------------------------------------------------------

pattern_conversion_enabled = os.environ.get('LUA_PATTERN_CONVERSION')

def int_or_none(v):
    if v:
        return int(v)
    else:
        return None

def build_patterns(strings):
    patterns = []

    for string in strings:
        if isinstance(string, bytes):
            string = string.decode('utf-8')

        if pattern_conversion_enabled:
            string = pattern_conversion.lua_pattern_to_regex(string)

        try:
            pattern = re.compile(string)
            patterns.append(pattern)
        except re.error as error:
            print('Pattern %s could not be compiled.  Error: %s.  Ignoring.' %
                    (string, str(error)))

    return patterns

# vim:ts=4:sw=4:et:tw=78
