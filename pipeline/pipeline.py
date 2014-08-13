import atexit
from distutils.version import StrictVersion
from os import environ as env
import os
import subprocess
import sys

import seesaw
from seesaw.externalprocess import WgetDownload, RsyncUpload
from seesaw.item import ItemInterpolation, ItemValue
from seesaw.pipeline import Pipeline
from seesaw.project import Project
from seesaw.task import LimitConcurrent
from seesaw.util import find_executable

# FIXME: This is a bit of a hack.
#
# Pipeline scripts are run with pwd set to their directory, which is why
# getcwd will (often) return the Right Thing.  A more robust solution would be
# nice, though.
sys.path.append(os.getcwd())

from archivebot import control
from archivebot import shared_config
from archivebot.seesaw import extensions
from archivebot.seesaw import monitoring
from archivebot.seesaw.tasks import GetItemFromQueue, StartHeartbeat, \
    SetFetchDepth, PreparePaths, WriteInfo, DownloadUrlFile, \
    RelabelIfAborted, MoveFiles, SetWarcFileSizeInRedis, StopHeartbeat, \
    MarkItemAsDone


VERSION = "20140810.01"
EXPIRE_TIME = 60 * 60 * 48  # 48 hours between archive requests
WPULL_EXE = find_executable('Wpull', None, [ './wpull' ])
PHANTOMJS = find_executable('PhantomJS', '1.9.7',
        ['phantomjs', './phantomjs'], '-v')

version_integer = (sys.version_info.major * 10) + sys.version_info.minor

assert version_integer >= 33, \
        "This pipeline requires Python >= 3.3.  You are running %s." % \
        sys.version

assert WPULL_EXE, 'No usable Wpull found.'
assert PHANTOMJS, 'PhantomJS 1.9.0 was not found.'
assert 'RSYNC_URL' in env, 'RSYNC_URL not set.'
assert 'REDIS_URL' in env, 'REDIS_URL not set.'

if StrictVersion(seesaw.__version__) < StrictVersion("0.1.8b1"):
    raise Exception(
        "Needs seesaw@python3/development version 0.1.8b1 or higher. "
        "You have version {0}".format(seesaw.__version__)
    )

RSYNC_URL = env['RSYNC_URL']
REDIS_URL = env['REDIS_URL']
LOG_CHANNEL = shared_config.log_channel()
PIPELINE_CHANNEL = shared_config.pipeline_channel()

# ------------------------------------------------------------------------------
# CONTROL CONNECTION
# ------------------------------------------------------------------------------

control_ref = control.Control.start(REDIS_URL, LOG_CHANNEL, PIPELINE_CHANNEL)
control = control_ref.proxy()

# ------------------------------------------------------------------------------
# SEESAW EXTENSIONS
# ------------------------------------------------------------------------------

extensions.install_stdout_extension(control)

# ------------------------------------------------------------------------------
# PIPELINE
# ------------------------------------------------------------------------------

project = Project(
        title = "ArchiveBot request handler"
)

def wpull_version():
    output = subprocess.check_output([WPULL_EXE, '--version'],
            stderr=subprocess.STDOUT)

    return output.decode('utf-8').strip()

class AcceptAny:
    def __contains__(self, item):
        return True

DEFAULT_USER_AGENT = \
    'ArchiveTeam ArchiveBot/%s (wpull %s) and not Mozilla/5.0 ' \
    '(Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) ' \
    'Chrome/36.0.1985.125 Safari/537.36'

class WpullArgs(object):
    def realize(self, item):
        user_agent = item['user_agent'] or (DEFAULT_USER_AGENT % (VERSION,
            wpull_version()))

        args = [WPULL_EXE,
            '-U', user_agent,
            '--header', 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            '--quiet',
            '-o', '%(item_dir)s/wpull.log' % item,
            '--database', '%(item_dir)s/wpull.db' % item,
            '--save-cookies', '%(cookie_jar)s' % item,
            '--no-check-certificate',
            '--delete-after',
            '--no-robots',
            '--span-hosts-allow=page-requisites,linked-pages',
            '--page-requisites',
            '--no-parent',
            '--inet4-only',
            '--timeout', '20',
            '--tries', '3',
            '--waitretry', '5',
            '--warc-file', '%(item_dir)s/%(warc_file_base)s' % item,
            '--warc-max-size', '10737418240',
            '--warc-header', 'operator: Archive Team',
            '--warc-header', 'downloaded-by: ArchiveBot',
            '--warc-header', 'archivebot-job-ident: %(ident)s' % item,
            '--python-script', 'wpull_hooks.py'
        ]

        if 'source_url_file' in item:
            self.add_args(args, ['-i', '%(source_url_file)s'], item)
        else:
            self.add_args(args, ['%(url)s'], item)

        self.add_args(args, ['%(recursive)s', '%(level)s', '%(depth)s'], item)

        if item['grabber'] == 'phantomjs':
            item.log_output('Telling wpull to use PhantomJS.')

            phantomjs_args = [
                '--phantomjs',
                '--phantomjs-scroll', item['phantomjs_scroll'],
                '--phantomjs-wait', item['phantomjs_wait']
            ]

            if item['no_phantomjs_smart_scroll']:
                phantomjs_args.append('--no-phantomjs-smart-scroll')

            item.log_output('Setting PhantomJS args: %s' % phantomjs_args)
            args.extend(phantomjs_args)

        return args

    @classmethod
    def add_args(cls, args, names, item):
        for name in names:
            value = name % item
            if value:
                args.append(value)

_, _, _, pipeline_id = monitoring.pipeline_id()

pipeline = Pipeline(
    GetItemFromQueue(control, pipeline_id, ao_only=env.get('AO_ONLY')),
    StartHeartbeat(control),
    SetFetchDepth(),
    PreparePaths(),
    WriteInfo(),
    DownloadUrlFile(control),
    WgetDownload(WpullArgs(),
    accept_on_exit_code=AcceptAny(),
    env={
        'ITEM_IDENT': ItemInterpolation('%(ident)s'),
        'LOG_KEY': ItemInterpolation('%(log_key)s'),
        'REDIS_URL': REDIS_URL,
        'PATH': os.environ['PATH']
    }),
    RelabelIfAborted(control),
    WriteInfo(),
    MoveFiles(),
    SetWarcFileSizeInRedis(control),
    LimitConcurrent(2,
        RsyncUpload(
            target = RSYNC_URL,
            target_source_path = ItemInterpolation("%(data_dir)s"),
            files=ItemValue("all_target_files"),
            extra_args = [
                '--partial',
                '--partial-dir', '.rsync-tmp'
            ]
        )
    ),
    StopHeartbeat(),
    MarkItemAsDone(control, EXPIRE_TIME)
)

def stop_control():
    control_ref.stop()

pipeline.on_cleanup += stop_control

# Activate system monitoring.
monitoring.start(pipeline, control, VERSION)

print('*' * 60)
print('Pipeline ID: %s' % pipeline_id)

if env.get('AO_ONLY'):
    print('!ao-only mode enabled')

print('*' * 60)
print()

# vim:ts=4:sw=4:et:tw=78
