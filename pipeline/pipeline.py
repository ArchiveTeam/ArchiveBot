import atexit
from distutils.version import StrictVersion
from os import environ as env
import os
import subprocess
import sys

import seesaw
from seesaw.externalprocess import RsyncUpload
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
from archivebot.seesaw.preflight import check_wpull_args
from archivebot.seesaw.wpull import WpullArgs
from archivebot.seesaw.tasks import GetItemFromQueue, StartHeartbeat, \
    SetFetchDepth, PreparePaths, WriteInfo, DownloadUrlFile, \
    WpullDownload, RelabelIfAborted, MoveFiles, SetWarcFileSizeInRedis, \
    StopHeartbeat, MarkItemAsDone, CheckIP


VERSION = "20150405.03"
PHANTOMJS_VERSION = '1.9.8'
EXPIRE_TIME = 60 * 60 * 48  # 48 hours between archive requests
WPULL_EXE = find_executable('Wpull', None, [ './wpull' ])
PHANTOMJS = find_executable('PhantomJS', PHANTOMJS_VERSION,
        ['phantomjs', './phantomjs', '../phantomjs'], '-v')

version_integer = (sys.version_info.major * 10) + sys.version_info.minor

assert version_integer >= 33, \
        "This pipeline requires Python >= 3.3.  You are running %s." % \
        sys.version

assert WPULL_EXE, 'No usable Wpull found.'
assert PHANTOMJS, 'PhantomJS %s was not found.' % PHANTOMJS_VERSION
assert 'RSYNC_URL' in env, 'RSYNC_URL not set.'
assert 'REDIS_URL' in env, 'REDIS_URL not set.'
assert 'FINISHED_WARCS_DIR' in env, 'FINISHED_WARCS_DIR not set.'

assert 'TMUX' in env or 'STY' in env or env.get('NO_SCREEN') == "1", \
        "Refusing to start outside of screen or tmux, set NO_SCREEN=1 to override"

if StrictVersion(seesaw.__version__) < StrictVersion("0.1.8b1"):
    raise Exception(
        "Needs seesaw@python3/development version 0.1.8b1 or higher. "
        "You have version {0}".format(seesaw.__version__)
    )

assert downloader not in ('ignorednick', 'YOURNICKHERE'), 'please use a real nickname'

RSYNC_URL = env['RSYNC_URL']
REDIS_URL = env['REDIS_URL']
LOG_CHANNEL = shared_config.log_channel()
PIPELINE_CHANNEL = shared_config.pipeline_channel()

# ------------------------------------------------------------------------------
# CONTROL CONNECTION
# ------------------------------------------------------------------------------

control = control.Control(REDIS_URL, LOG_CHANNEL, PIPELINE_CHANNEL)

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

DEFAULT_USER_AGENT = \
    'ArchiveTeam ArchiveBot/%s (wpull %s) and not Mozilla/5.0 ' \
    '(Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) ' \
    'Chrome/39.0.2171.95 Safari/537.36' % (VERSION, wpull_version())

_, _, _, pipeline_id = monitoring.pipeline_id()

wpull_args = WpullArgs(
    default_user_agent=DEFAULT_USER_AGENT, wpull_exe=WPULL_EXE,
    phantomjs_exe=PHANTOMJS, 
    finished_warcs_dir=os.environ["FINISHED_WARCS_DIR"]
)

pipeline = Pipeline(
    CheckIP(),
    GetItemFromQueue(control, pipeline_id, downloader, ao_only=env.get('AO_ONLY')),
    StartHeartbeat(control),
    SetFetchDepth(),
    PreparePaths(),
    WriteInfo(),
    DownloadUrlFile(control),
    WpullDownload(
        control,
        wpull_args,
        accept_on_exit_code=[0,4,5,6,7,8],
        max_tries=None,
        env={
            'ITEM_IDENT': ItemInterpolation('%(ident)s'),
            'LOG_KEY': ItemInterpolation('%(log_key)s'),
            'REDIS_URL': REDIS_URL,
            'PATH': os.environ['PATH']
        }
    ),
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
    control.unregister_pipeline(pipeline_id)

pipeline.on_cleanup += stop_control

# Activate system monitoring.
monitoring.start(pipeline, control, VERSION, downloader)

check_wpull_args(wpull_args)

print('*' * 60)
print('Pipeline ID: %s' % pipeline_id)

if env.get('AO_ONLY'):
    print('!ao-only mode enabled')

print('*' * 60)
print()

# vim:ts=4:sw=4:et:tw=78
