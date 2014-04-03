import os
import sys
import redis
import atexit
import subprocess

# FIXME: This is a bit of a hack.
#
# Pipeline scripts are run with pwd set to their directory, which is why
# getcwd will (often) return the Right Thing.  A more robust solution would be
# nice, though.
sys.path.append(os.getcwd())

from archivebot import shared_config
from archivebot import control
from archivebot.seesaw import monitoring
from archivebot.seesaw import extensions
from archivebot.seesaw.tasks import *

from os import environ as env
from seesaw.project import *
from seesaw.item import *
from seesaw.task import *
from seesaw.pipeline import *
from seesaw.externalprocess import *
from seesaw.util import find_executable

VERSION = "20140328.01"
EXPIRE_TIME = 60 * 60 * 48  # 48 hours between archive requests
WPULL_EXE = find_executable('Wpull', None, [ './wpull' ])

if not WPULL_EXE:
    raise Exception("No usable Wpull found.")

if 'RSYNC_URL' not in env:
    raise Exception('RSYNC_URL not set.')

if 'REDIS_URL' not in env:
    raise Exception('REDIS_URL not set.')

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

class WpullArgs(object):
    def realize(self, item):

        args = [WPULL_EXE,
            '-U', 'ArchiveTeam ArchiveBot/%s (wpull %s)' % (VERSION,
                wpull_version()),
            '--quiet',
            '--ascii-print',
            '-o', '%(item_dir)s/wpull.log' % item,
            '--database', '%(item_dir)s/wpull.db' % item,
            '--save-cookies', '%(cookie_jar)s' % item,
            '--no-check-certificate',
            '--delete-after',
            '--no-robots',
            '--page-requisites',
            '--no-parent',
            '--timeout', '20',
            '--tries', '10',
            '--waitretry', '5',
            '--warc-file', '%(item_dir)s/%(warc_file_base)s' % item,
            '--warc-header', 'operator: Archive Team',
            '--warc-header', 'downloaded-by: ArchiveBot',
            '--warc-header', 'archivebot-job-ident: %(ident)s' % item,
            '--python-script', 'wpull_hooks.py',
            '%(url)s' % item
        ]

        self.add_args(args, ['%(recursive)s', '%(level)s', '%(depth)s'], item)

        return args

    @classmethod
    def add_args(cls, args, names, item):
        for name in names:
            value = name % item
            if value:
                args.append(value)

_, _, _, pipeline_id = monitoring.pipeline_id()

pipeline = Pipeline(
    GetItemFromQueue(control, pipeline_id),
    StartHeartbeat(control),
    SetFetchDepth(),
    PreparePaths(),
    WriteInfo(),
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
            files = [
                ItemInterpolation('%(target_warc_file)s'),
                ItemInterpolation('%(target_info_file)s')
            ]
        )
    ),
    StopHeartbeat(),
    MarkItemAsDone(control, EXPIRE_TIME)
)

def stop_control():
    control_ref.stop()

atexit.register(stop_control)
pipeline.on_cleanup += stop_control

# Activate system monitoring.
monitoring.start(pipeline, control, VERSION)

print('*' * 60)
print('Pipeline ID: %s' % pipeline_id)
print('*' * 60)
print()

# vim:ts=4:sw=4:et:tw=78
