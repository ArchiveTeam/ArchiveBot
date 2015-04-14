import datetime
import functools
import glob
import json
import os
import shutil
import time
import requests
import socket

from seesaw.externalprocess import WgetDownload
from seesaw.task import Task, SimpleTask
from tornado.ioloop import IOLoop
import tornado.ioloop

from archivebot.control import ConnectionError


class CheckIP(SimpleTask):
    def __init__(self):
        SimpleTask.__init__(self, "CheckIP")

    def process(self, item):
        item.log_output('Checking IP address.')
        ip_set = set()

        ip_set.add(socket.gethostbyname('twitter.com'))
        ip_set.add(socket.gethostbyname('facebook.com'))
        ip_set.add(socket.gethostbyname('youtube.com'))
        ip_set.add(socket.gethostbyname('microsoft.com'))
        ip_set.add(socket.gethostbyname('icanhas.cheezburger.com'))
        ip_set.add(socket.gethostbyname('archiveteam.org'))

        if len(ip_set) != 6:
            item.log_output('Got IP addresses: {0}'.format(ip_set))
            item.log_output(
                'Are you behind a firewall/proxy? That is a big no-no!')
            raise Exception(
                'Are you behind a firewall/proxy? That is a big no-no!')


class RetryMixin(object):
    retry_delay = 5
    cancelable = False

    def schedule_retry(self, item):
        item.may_be_canceled = self.cancelable

        IOLoop.instance().add_timeout(datetime.timedelta(seconds=self.retry_delay),
               functools.partial(self.retry, item))

    def retry(self, item):
        if not item.canceled:
            item.may_be_canceled = False

            self.process(item)

    def notify_retry(self, reason, item):
        item.log_output("%s. Retrying %s in %s seconds." %
                (reason, self, self.retry_delay))
   
    def notify_connection_error(self, item):
        self.notify_retry('Lost connection to ArchiveBot controller', item)

class RetryableTask(Task, RetryMixin):
    retry_delay = 5
    cancelable = False

    def enqueue(self, item):
        self.start_item(item)
        item.log_output('Starting %s for %s' % (self, item.description()))
        self.process(item)

# ------------------------------------------------------------------------------

class GetItemFromQueue(RetryableTask):
    def __init__(self, control, pipeline_id, pipeline_nick, retry_delay=5, ao_only=False):
        RetryableTask.__init__(self, 'GetItemFromQueue')
        self.control = control
        self.pipeline_id = pipeline_id
        self.pipeline_nick = pipeline_nick
        self.retry_delay = retry_delay
        self.cancelable = True
        self.pipeline_queue = 'pending:%s' % self.pipeline_id
        self.ao_only = ao_only

    def process(self, item):
        try: 
            ident, job_data = self.control.reserve_job(self.pipeline_id,
                    self.pipeline_nick, self.ao_only)

            if ident == None:
                self.schedule_retry(item)
            else:
                item['fetch_depth'] = job_data.get('fetch_depth')
                item['ident'] = ident
                item['log_key'] = job_data.get('log_key')
                item['pipeline_id'] = self.pipeline_id
                item['queued_at'] = job_data.get('queued_at')
                item['slug'] = job_data.get('slug')
                item['started_by'] = job_data.get('started_by')
                item['started_in'] = job_data.get('started_in')
                item['url'] = job_data.get('url')
                item['url_file'] = job_data.get('url_file')
                item['grabber'] = job_data.get('grabber')
                item['user_agent'] = job_data.get('user_agent')
                item['no_offsite_links'] = job_data.get('no_offsite_links')
                item['phantomjs_wait'] = job_data.get('phantomjs_wait')
                item['phantomjs_scroll'] = job_data.get('phantomjs_scroll')
                item['no_phantomjs_smart_scroll'] = \
                    job_data.get('no_phantomjs_smart_scroll')

                item.log_output('Received item %s.' % ident)

                self.complete_item(item)
        except ConnectionError:
            self.notify_connection_error(item)
            self.schedule_retry(item)

# ------------------------------------------------------------------------------

class StartHeartbeat(SimpleTask):
    def __init__(self, control):
        SimpleTask.__init__(self, 'StartHeartbeat')
        self.control = control

    def process(self, item):
        cb = tornado.ioloop.PeriodicCallback(
                functools.partial(self.send_heartbeat, item),
                1000)

        item['heartbeat'] = cb

        cb.start()

    def send_heartbeat(self, item):
        self.control.heartbeat(item['ident'])

# ------------------------------------------------------------------------------

class SetFetchDepth(SimpleTask):
    def __init__(self):
        SimpleTask.__init__(self, 'SetFetchDepth')

    def process(self, item):
        depth = item['fetch_depth']

        if depth == 'shallow':
            item['recursive'] = False
        else:
            item['recursive'] = True
            item['depth'] = depth

# ------------------------------------------------------------------------------

class TargetPathMixin(object):
    def set_target_paths(self, item):
        item['target_warc_file_prefix'] = '%(data_dir)s/%(warc_file_base)s' % item
        item['target_info_file'] = '%(data_dir)s/%(warc_file_base)s.json' % item

    def get_source_warc_filenames(self, item):
        return list(sorted(
            glob.glob('%(source_warc_file_prefix)s*.warc.gz' % item)
        ))

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
        item['source_warc_file_prefix'] = '%(item_dir)s/%(warc_file_base)s' % item
        item['source_info_file'] = '%(item_dir)s/%(warc_file_base)s.json' % item
        item['cookie_jar'] = '%(item_dir)s/cookies.txt' % item

        self.set_target_paths(item)

# ------------------------------------------------------------------------------

class WpullDownload(WgetDownload, RetryMixin):
    def __init__(self, control, *args, **kwargs):
        WgetDownload.__init__(self, *args, **kwargs)

        self.control = control

    def process(self, item):
        try:
            if self.control.is_aborted(item['ident']):
                item.log_output('%(ident)s aborted, not starting wpull' % item)
                self.complete_item(item)
            else:
                WgetDownload.process(self, item)
        except ConnectionError:
            self.notify_connection_error(item)
            self.schedule_retry(item)

# ------------------------------------------------------------------------------

class RelabelIfAborted(RetryableTask, TargetPathMixin):
    def __init__(self, control):
        RetryableTask.__init__(self, 'RelabelIfAborted')
        self.control = control

    def process(self, item):
        try:
            if self.control.is_aborted(item['ident']):
                item['aborted'] = True
                item['warc_file_base'] = '%(warc_file_base)s-aborted' % item

                self.set_target_paths(item)

                item.log_output('Adjusted target WARC path to %(target_warc_file_prefix)s' %
                        item)

            self.complete_item(item)
        except ConnectionError:
            self.notify_connection_error(item)
            self.schedule_retry(item)

# ------------------------------------------------------------------------------

class MoveFiles(SimpleTask, TargetPathMixin):
    def __init__(self):
        SimpleTask.__init__(self, "MoveFiles")

    def process(self, item):
        item['target_warc_files'] = self.rename_warc_files(item)
        item['all_target_files'] = item['target_warc_files'] + [item['target_info_file']]

        if 'target_url_file' in item:
            item['all_target_files'].append(item['target_url_file'])
            os.rename(item['source_url_file'], item['target_url_file'])

        os.rename(item['source_info_file'], item['target_info_file'])
        shutil.rmtree("%(item_dir)s" % item)

    def rename_warc_files(self, item):
        target_filenames = []

        for source_filename in self.get_source_warc_filenames(item):
            assert source_filename.startswith(item['source_warc_file_prefix'])
            target_filename = source_filename.replace(
                item['source_warc_file_prefix'],
                item['target_warc_file_prefix'],
                1
            )
            os.rename(source_filename, target_filename)
            target_filenames.append(target_filename)

        return target_filenames

# ------------------------------------------------------------------------------

class WriteInfo(SimpleTask):
    def __init__(self):
        SimpleTask.__init__(self, 'WriteInfo')

    def process(self, item):
        # The "aborted" key might not have been written by any prior process,
        # i.e. if the job wasn't aborted.  For accessor convenience, we add
        # that key here.
        if 'aborted' in item:
            aborted = item['aborted']
        else:
            aborted = False

        # This JSON object's fieldset is an externally visible interface.
        # Adding fields is fine; changing existing ones, not so much.
        item['info'] = {
                'aborted': aborted,
                'fetch_depth': item['fetch_depth'],
                'pipeline_id': item['pipeline_id'],
                'queued_at': item['queued_at'],
                'started_by': item['started_by'],
                'started_in': item['started_in'],
                'url': item['url'],
                'url_file': item['url_file']
        }

        with open(item['source_info_file'], 'w') as f:
            f.write(json.dumps(item['info'], indent=True))

# ------------------------------------------------------------------------------

class DownloadUrlFile(RetryableTask):
    def __init__(self, control):
        RetryableTask.__init__(self, 'DownloadUrlFile')

        self.control = control

    def process(self, item):
        if not item['url_file']:
            self.complete_item(item)
            return

        try:
            r = requests.get(item['url_file'], stream=True)

            item['source_url_file'] = \
                '%(source_warc_file_prefix)s-urls.txt' % item
            item['target_url_file'] = \
                '%(target_warc_file_prefix)s-urls.txt' % item

            # Files could be huge, and we do not care about their contents or
            # encoding.  (We leave parsing the file to the crawler.)
            with open(item['source_url_file'], 'wb') as f:
                for chunk in r.iter_content(4096):
                    f.write(chunk)

            size = os.stat(item['source_url_file']).st_size
            item.log_output('Downloaded {0} bytes from {1}'.format(size, item['url_file']))
            self.complete_item(item)
        except requests.exceptions.RequestException as e:
            item.log_output('Exception raised in DownloadUrlFile: {}'.format(e))

            # It's possible that the URL that was originally provided has gone
            # bad in some way.  We re-read the URL to allow the job submitter
            # to make changes.  If a URL is present, we replace the existing
            # URL in the item.  If a URL is not present, we keep what we have.
            item.log_output('Refreshing file URL from ArchiveBot')
            new_url_file = self.control.get_url_file(item['ident'])

            if new_url_file:
                item['url_file'] = new_url_file

            self.schedule_retry(item)

# ------------------------------------------------------------------------------

class SetWarcFileSizeInRedis(RetryableTask):
    def __init__(self, control):
        RetryableTask.__init__(self, 'SetWarcFileSizeInRedis')
        self.control = control

    def process(self, item):
        try:
            self.control.set_warc_size(item['ident'],
                    *item['target_warc_files'])
            self.complete_item(item)
        except ConnectionError:
            self.notify_connection_error(item)
            self.schedule_retry(item)

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

class MarkItemAsDone(RetryableTask):
    def __init__(self, control, expire_time):
        RetryableTask.__init__(self, 'MarkItemAsDone')
        self.control = control
        self.expire_time = expire_time

    def process(self, item):
        try:
            self.control.mark_done(item, self.expire_time)
            self.complete_item(item)
        except ConnectionError:
            self.notify_connection_error(item)
            self.schedule_retry(item)

# vim:ts=4:sw=4:et:tw=78
