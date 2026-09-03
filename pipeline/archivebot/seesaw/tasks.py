import datetime
import functools
import glob
import gzip
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

from redis.exceptions import ConnectionError


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

        # Domains that are not supposed to resolve
        for domain in ('domain.invalid', 'nxdomain.archiveteam.org', 'www'):
            try:
                ip = socket.gethostbyname(domain)
            except socket.gaierror as e:
                if e.errno != socket.EAI_NONAME:
                    raise
            else:
                item.log_output('Got an IP address ({}) for {} instead of NXDOMAIN'.format(ip, domain))
                item.log_output('Are you behind a firewall/proxy or have a misconfigured resolv.conf? That is a big no-no!')
                raise Exception('Are you behind a firewall/proxy or have a misconfigured resolv.conf? That is a big no-no!')


class CheckLocalWebserver(SimpleTask):
    def __init__(self):
        SimpleTask.__init__(self, "CheckLocalWebserver")

    def process(self, item):
        for port in (80, 443, 8000, 8080, 8443):
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            try:
                s.connect(('localhost', port))
            except socket.error:
                pass
            else:
                item.log_output('Was able to connect to localhost:{}'.format(port))
                item.log_output('Are you running a web server on the same machine as the pipeline? That is a big no-no!')
                raise Exception('Are you running a web server on the same machine as the pipeline? That is a big no-no!')


class RetryableTask(Task):
    retry_delay = 5
    cancelable = False

    def enqueue(self, item):
        self.start_item(item)
        item.log_output('Starting %s for %s' % (self, item.description()))
        self.process(item)

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

# ------------------------------------------------------------------------------

class GetItemFromQueue(RetryableTask):
    def __init__(self, control, pipeline_id, pipeline_nick, retry_delay=5,
        ao_only=False, large=False, version_check = None):
        RetryableTask.__init__(self, 'GetItemFromQueue')
        self.control = control
        self.pipeline_id = pipeline_id
        self.pipeline_nick = pipeline_nick
        self.retry_delay = retry_delay
        self.cancelable = True
        self.pipeline_queue = 'pending:%s' % self.pipeline_id
        self.ao_only = ao_only
        self.large = large
        # (versionOnStartup, versionFunc) where the latter is an argument-less function returning the current version of the files
        self.version_on_startup, self.version_func = version_check

    def process(self, item):
        # Check that the files haven't changed since the pipeline was launched
        currentVersion = self.version_func()
        if currentVersion != self.version_on_startup:
            item.log_output('Version has changed from {!r} on startup to {!r} now'.format(self.version_on_startup, currentVersion))
            raise Exception('Version has changed from {!r} on startup to {!r} now'.format(self.version_on_startup, currentVersion))

        try: 
            ident, job_data = self.control.reserve_job(self.pipeline_id,
                    self.pipeline_nick, self.ao_only, self.large)

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
                item['user_agent'] = job_data.get('user_agent')
                item['no_offsite_links'] = job_data.get('no_offsite_links')
                item['no_cookies'] = job_data.get('no_cookies')
                item['youtube_dl'] = job_data.get('youtube_dl')

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

class Wpull(WgetDownload):
    def on_subprocess_end(self, item, returncode):
        item['wpull_returncode'] = returncode
        super().on_subprocess_end(item, returncode)

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

class CompressLogIfFailed(SimpleTask, TargetPathMixin):
    def __init__(self):
        SimpleTask.__init__(self, 'CompressLogIfNoMetaWarc')

    def process(self, item):
        #TODO: Instead of checking the exit status of wpull, this should check whether wpull wrote a meta WARC (and whether it contains the log).
        #TODO: If the disk is almost full, this may crash, which would probably mean a loss of the log file (and possibly also anything else).
        if item['wpull_returncode'] not in (0, 4, 8):
            item['source_log_file'] = '%(item_dir)s/%(warc_file_base)s-wpull.log.gz' % item
            item['target_log_file'] = '%(data_dir)s/%(warc_file_base)s-wpull.log.gz' % item
            with open('%(item_dir)s/wpull.log' % item, 'rb') as fI:
                with gzip.GzipFile(item['source_log_file'], 'w', compresslevel = 9) as fO:
                    shutil.copyfileobj(fI, fO)

# ------------------------------------------------------------------------------

class MoveFiles(SimpleTask, TargetPathMixin):
    def __init__(self, target_directory):
        SimpleTask.__init__(self, "MoveFiles")
        self.target_directory = target_directory

    def process(self, item):
        item['target_warc_files'] = self.rename_warc_files(item)
        item['all_target_files'] = item['target_warc_files'] + [item['target_info_file']]

        if 'target_url_file' in item:
            item['all_target_files'].append(item['target_url_file'])
            os.rename(item['source_url_file'], item['target_url_file'])

        if 'target_log_file' in item:
            item['all_target_files'].append(item['target_log_file'])
            os.rename(item['source_log_file'], item['target_log_file'])

        os.rename(item['source_info_file'], item['target_info_file'])
        shutil.rmtree("%(item_dir)s" % item)

        for fn in item['all_target_files']:
            shutil.move(fn, self.target_directory)

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
