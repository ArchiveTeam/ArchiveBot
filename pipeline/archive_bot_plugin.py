# The ArchiveBot plugin will be split across multiple modules, but
# sys.path for plugins does not include the plugin file's directory.
# We add that here.
import os
import sys
sys.path.append(os.path.dirname(os.path.realpath(__file__)))

# Import wpull bits used by the plugin.
from wpull.application.hook import Actions
from wpull.application.plugin import WpullPlugin, PluginFunctions, hook, event
from wpull.pipeline.app import AppSession
from wpull.pipeline.item import URLRecord
from wpull.pipeline.session import ItemSession
from wpull.protocol.abstract.request import BaseResponse
from wpull.stats import Statistics
from wpull.url import URLInfo


def log_info(*args):
    print(*args)


class ArchiveBotPlugin(WpullPlugin):
    def activate(self):
        super().activate()

        log_info('ArchiveBot hooks activated')

    def deactivate(self):
        super().deactivate()

        log_info('ArchiveBot hooks deactivated')

    @hook(PluginFunctions.accept_url)
    def accept_url(self,
                   item_session: ItemSession,
                   verdict: bool,
                   reasons: dict):
        return True

    @event(PluginFunctions.queued_url)
    def queued_url(self, url_info: URLInfo):
        pass

    @event(PluginFunctions.dequeued_url)
    def dequeued_url(self, url_info: URLInfo, record_info: URLRecord):
        pass

    @hook(PluginFunctions.handle_pre_response)
    def handle_response(self, item_session: ItemSession):
        return Actions.NORMAL

    @hook(PluginFunctions.handle_response)
    def handle_response(self, item_session: ItemSession):
        return Actions.NORMAL

    @hook(PluginFunctions.handle_error)
    def handle_error(self, item_session: ItemSession, error: BaseException):
        return Actions.NORMAL

    @event(PluginFunctions.finishing_statistics)
    def finishing_statistics(self,
                             app_session: AppSession,
                             statistics: Statistics):
        pass

    @hook(PluginFunctions.exit_status)
    def exit_status(self, app_session: AppSession, exit_code: int):
        return exit_code

    @hook(PluginFunctions.wait_time)
    def wait_time(self, seconds: float, item_session: ItemSession, error):
        return seconds
