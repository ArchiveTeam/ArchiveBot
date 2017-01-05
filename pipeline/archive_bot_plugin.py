""" ArchiveBot wpull 2.x plugin (replaces 1.x hooks)

This module implements the integration layer between ArchiveBot and wpull.  In
particular, it handles ignore settings, settings changes, dashboard reporting,
and aborts.
"""

# The ArchiveBot plugin will be split across multiple modules, but
# sys.path for plugins does not include the plugin file's directory.
# We add that here.
import os
import sys
import random
import time
import logging
import re
sys.path.append(os.path.dirname(os.path.realpath(__file__)))

# Import wpull bits used by the plugin.
from wpull.application.hook import Actions
from wpull.application.plugin import WpullPlugin, PluginFunctions, hook, event
from wpull.pipeline.app import AppSession
from wpull.pipeline.item import URLRecord
from wpull.pipeline.session import ItemSession
from wpull.stats import Statistics
from wpull.url import URLInfo

from archivebot import shared_config
from archivebot.control import Control
from archivebot.wpull import settings as mod_settings

# dupespotter plugin:
import archivebot.wpull.plugin

def _extract_response_code(item_session: ItemSession) -> int:
    statcode = 0

    try:
        # duck typing: assume the response is
        # wpull.protocol.http.request.Response
        statcode = item_session.response.status_code
    except (AttributeError, KeyError):
        pass

    try:
        # duck typing: assume the response is
        # wpull.protocol.ftp.request.Response
        statcode = item_session.response.reply.code
    except (AttributeError, KeyError):
        pass

    return statcode

def _extract_item_size(item_session: ItemSession) -> int:
    try:
        return item_session.response.body.size()
    except (AttributeError, KeyError):
        return 0

def is_error(statcode, err):
    '''
    Determines whether a given status code/error code combination should be
    flagged as an error.
    '''
    # 5xx: yes
    if statcode >= 500:
        return True

    # Response code zero with non-OK wpull code: yes
    if err != 'OK':
        return True

    # Could be an error, but we don't know it as such
    return False

def is_warning(statcode):
    '''
    Determines whether a given status code/error code combination should be
    flagged as a warning.
    '''
    return statcode >= 400 and statcode < 500

class ArchiveBotPlugin(WpullPlugin):
    last_age = 0

    ident = None
    redis_url = None
    log_key = None
    log_channel = None
    pipeline_channel = None
    control = None

    settings = None
    settings_listener = None

    logger = None

    def log_ignore(self, url, pattern, source):
        packet = dict(
            ts=time.time(),
            url=url,
            pattern=pattern,
            type='ignore',
            source=source
        )

        self.control.log(packet, self.ident, self.log_key)

    def maybe_log_ignore(self, url, pattern, source):
        if not self.settings.suppress_ignore_reports():
            self.log_ignore(url, pattern, source)

        self.logger.info('Ignore %s using pattern %s', url, pattern)

    def log_result(self, url, statcode, error):
        packet = dict(
            ts=time.time(),
            url=url,
            response_code=statcode,
            wget_code=error,
            is_error=is_error(statcode, error),
            is_warning=is_warning(statcode),
            type='download'
        )

        self.control.log(packet, self.ident, self.log_key)

    def print_log(self, *args):
        print(*args)
        sys.stdout.flush()
        self.logger.info(' '.join(str(arg) for arg in args))

    def handle_result(self, item_session: ItemSession, error_info:
                      BaseException=None):

        error = 'OK'
        statcode = _extract_response_code(item_session)

        self.control.update_bytes_downloaded(_extract_item_size(item_session))

        # Check raw and normalized URL against ignore list
        pattern = self.settings.ignore_url(item_session.url_record)
        if pattern:
            self.maybe_log_ignore(item_session.url_record.url, pattern, 'handle_result')
            return Actions.FINISH

        if error_info:
            error = str(error_info)

        self.log_result(item_session.url_record.url, statcode, error)

        settings_age = self.settings.age()
        if self.last_age < settings_age:
            self.last_age = settings_age
            self.print_log("Settings updated: ", self.settings.inspect())
            self.app_session.factory['PipelineSeries'].concurrency = self.settings.concurrency()

        # See that the settings listener is online
        self.settings_listener.check()

        if self.settings.abort_requested():
            self.print_log("Wpull terminating on bot command")

            while True:
                try:
                    self.control.mark_aborted(self.ident)
                    #Since wpull does not call .deactivate() as at 2.0.1:
                    self.settings_listener.stop()
                    break
                except ConnectionError as err:
                    self.print_log("Failed to mark job aborted in controller:"
                        " {}".format(err))
                    time.sleep(5)

            return Actions.STOP

        return Actions.NORMAL

    def activate(self):
        self.ident = os.environ['ITEM_IDENT']
        self.redis_url = os.environ['REDIS_URL']
        self.log_key = os.environ['LOG_KEY']
        self.log_channel = shared_config.log_channel()
        self.pipeline_channel = shared_config.pipeline_channel()
        self.control = Control(self.redis_url, self.log_channel, self.pipeline_channel)

        self.settings = mod_settings.Settings()
        self.settings_listener = mod_settings.Listener(self.redis_url, self.settings,
                                                       self.control, self.ident)
        self.settings_listener.start()

        self.last_age = 0
        self.logger = logging.getLogger('archivebot.pipeline.wpull_plugin')

        self.logger.info('wpull plugin initialization complete for job ID '
                         '{}'.format(self.ident))

        archivebot.wpull.plugin.activate(self.app_session)
        self.logger.info('wpull dupespotter subsystem loaded for job ID '
                         '{}'.format(self.ident))


        super().activate()
        self.logger.info('wpull plugin activated')

    def deactivate(self):
        super().deactivate()

        self.logger.info('stopping settings listener')
        self.settings_listener.stop()

        self.logger.info('wpull plugin deactivated')

    @hook(PluginFunctions.accept_url)
    def accept_url(self,
                   item_session: ItemSession,
                   verdict: bool,
                   reasons: dict):

        url = item_session.url_record.url_info

        if (url.scheme not in ['https', 'http', 'ws', 'wss', 'ftp', 'gopher']
                or url.path in [None, '/', '']):
            return False

        pattern = self.settings.ignore_url(item_session.url_record)
        if pattern:
            self.maybe_log_ignore(url.raw, pattern, 'accept_url')
            return False

        return verdict

    @event(PluginFunctions.queued_url)
    def queued_url(self, url_info: URLInfo):
        # Report one URL added to the queue
        self.control.update_items_queued(1)

    @event(PluginFunctions.dequeued_url)
    def dequeued_url(self, url_info: URLInfo, record_info: URLRecord):
        # Report one URL removed from the queue
        self.control.update_items_downloaded(1)

    @hook(PluginFunctions.handle_pre_response)
    def handle_pre_response(self, item_session: ItemSession):
        url = item_session.url_record.url_info

        try:
            # duck typing: assume it was HTTP-like
            # like wpull.protocol.http.request.Response
            response = item_session.response

            ICY_FIELD_PATTERN = re.compile('Icy-|Ice-|X-Audiocast-')
            ICY_VALUE_PATTERN = re.compile('icecast', re.IGNORECASE)

            if response.version is 'ICY':
                self.maybe_log_ignore(url, '[icy version]', 'handle_pre_response')
                return Actions.FINISH

            for field, value in response.fields.get_all():
                if ICY_FIELD_PATTERN.match(field):
                    self.maybe_log_ignore(url.raw, '[icy version]',
                                          'handle_pre_response')
                    return Actions.FINISH

                if field == 'Server' and ICY_VALUE_PATTERN.match(value):
                    self.maybe_log_ignore(url.raw, '[icy server]',
                                          'handle_pre_response')
                    return Actions.FINISH

        except (AttributeError, KeyError):
            pass

        return Actions.NORMAL

    @hook(PluginFunctions.handle_response)
    def handle_response(self, item_session: ItemSession):
        return self.handle_result(item_session)

    @hook(PluginFunctions.handle_error)
    def handle_error(self, item_session: ItemSession, error: BaseException):
        return self.handle_result(item_session, error)

    @event(PluginFunctions.finishing_statistics)
    def finishing_statistics(self,
                             app_session: AppSession,
                             statistics: Statistics):
        self.print_log(" ", statistics.size, "bytes.")

    @hook(PluginFunctions.exit_status)
    def exit_status(self, app_session: AppSession, exit_code: int):
        self.logger.info('Advising control task {} and settings listener to stop '
                         'pending termination for ident '
                         '{}'.format(self.control, self.ident))
        self.control.advise_exiting()
        self.settings_listener.stop()
        return exit_code

    @hook(PluginFunctions.wait_time)
    def wait_time(self, seconds: float, item_session: ItemSession, error):
        sl, sh = self.settings.delay_time_range()
        return random.uniform(sl, sh) / 1000

# vim: ts=4:sw=4:et:tw=78
