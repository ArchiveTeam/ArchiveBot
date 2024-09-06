import atexit
import datetime
import os
import subprocess
import sys
from distutils.version import StrictVersion
from os import environ as env

import seesaw
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

from archivebot import control, shared_config
from archivebot.seesaw import extensions, monitoring
from archivebot.seesaw.dnspythoncrash import test as dnspython_crash_fixed
from archivebot.seesaw.preflight import check_wpull_args
from archivebot.seesaw.tasks import (CheckIP, CheckLocalWebserver,
                                     CompressLogIfFailed, DownloadUrlFile,
                                     GetItemFromQueue, MarkItemAsDone,
                                     MoveFiles, PreparePaths, RelabelIfAborted,
                                     SetFetchDepth, StartHeartbeat,
                                     StopHeartbeat, Wpull, WriteInfo)
from archivebot.seesaw.wpull import WpullArgs

WPULL_VERSION = ('2.0.3')
EXPIRE_TIME = 60 * 60 * 48  # 48 hours between archive requests
WPULL_EXE = find_executable('Wpull', WPULL_VERSION, ['wpull', './wpull'], '--version')
YOUTUBE_DL = find_executable('youtube-dl', None, ['./youtube-dl'], '--version')

version_integer = (sys.version_info.major * 10) + sys.version_info.minor

assert version_integer >= 33, \
        "This pipeline requires Python >= 3.3.  You are running %s." % \
        sys.version

if not os.environ.get('NO_SEGFAULT_340'):
    assert sys.version_info[:3] != (3, 4, 0), \
        "Python 3.4.0 should not be used. It may segfault. " \
        "Set NO_SEGFAULT_340=1 if your Python is patched. " \
        "See https://bugs.python.org/issue21435"

assert WPULL_EXE, 'No usable Wpull found.'
assert YOUTUBE_DL, 'No usable youtube-dl found.'
assert 'REDIS_URL' in env, 'REDIS_URL not set.'
assert 'FINISHED_WARCS_DIR' in env, 'FINISHED_WARCS_DIR not set.'

if 'WARC_MAX_SIZE' in env:
    WARC_MAX_SIZE = env['WARC_MAX_SIZE']
else:
    WARC_MAX_SIZE = '5368709120'
WPULL_MONITOR_DISK = env.get('WPULL_MONITOR_DISK', '5120m')
WPULL_MONITOR_MEMORY = env.get('WPULL_MONITOR_MEMORY', '50m')

assert 'TMUX' in env or 'STY' in env or env.get('NO_SCREEN') == "1", \
        "Refusing to start outside of screen or tmux, set NO_SCREEN=1 to override"

if StrictVersion(seesaw.__version__) < StrictVersion("0.1.8b1"):
    raise Exception(
        "Needs seesaw@python3/development version 0.1.8b1 or higher. "
        "You have version {0}".format(seesaw.__version__)
    )

assert downloader not in ('ignorednick', 'YOURNICKHERE'), 'please use a real nickname'

assert datetime.datetime.now(datetime.timezone.utc).astimezone().tzinfo.utcoffset(None).seconds == 0, 'Please set the time zone to UTC'

assert dnspython_crash_fixed(), 'Broken crash-prone dnspython found'

REDIS_URL = env['REDIS_URL']
LOG_CHANNEL = shared_config.log_channel()
PIPELINE_CHANNEL = shared_config.pipeline_channel()
OPENSSL_CONF = env.get('OPENSSL_CONF')
TMPDIR = env.get('TMPDIR')

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

#FIXME: Same hack as above; seesaw executes pipeline.py with the pipeline dir as the cwd.
# __file__ can't be used because seesaw exec()s the file contents rather than importing the file.
REPO_DIRECTORY = os.path.dirname(os.path.realpath('.'))

def pipeline_version():
    # Returns something like 20190820.5cd1e38
    output = subprocess.check_output(['git', 'show', '-s', '--format=format:%cd.%h', '--date=format:%Y%m%d'], cwd = REPO_DIRECTORY)
    return output.decode('utf-8').strip()

def wpull_version():
    output = subprocess.check_output([WPULL_EXE, '--version'],
            stderr=subprocess.STDOUT)

    return output.decode('utf-8').strip()

class AcceptAny:
    def __contains__(self, item):
        return True

VERSION = pipeline_version()
DEFAULT_USER_AGENT = \
    'ArchiveTeam ArchiveBot/%s (wpull %s) and not Mozilla/5.0 ' \
    '(Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) ' \
    'Chrome/42.0.2311.90 Safari/537.36' % (VERSION, wpull_version())

_, _, _, pipeline_id = monitoring.pipeline_id()

wpull_args = WpullArgs(
    default_user_agent=DEFAULT_USER_AGENT,
    wpull_exe=WPULL_EXE,
    youtube_dl_exe=YOUTUBE_DL,
    finished_warcs_dir=os.environ["FINISHED_WARCS_DIR"],
    warc_max_size=WARC_MAX_SIZE,
    monitor_disk=WPULL_MONITOR_DISK,
    monitor_memory=WPULL_MONITOR_MEMORY,
    warc_tempdir=TMPDIR if TMPDIR else os.getcwd(),
)

check_wpull_args(wpull_args)

wpull_env = dict(os.environ)
wpull_env['ITEM_IDENT'] = ItemInterpolation('%(ident)s')
wpull_env['LOG_KEY'] = ItemInterpolation('%(log_key)s')
wpull_env['REDIS_URL'] = REDIS_URL

if OPENSSL_CONF:
    wpull_env['OPENSSL_CONF'] = OPENSSL_CONF
if TMPDIR:
    wpull_env['TMPDIR'] = TMPDIR

pipeline = Pipeline(
    CheckIP(),
    CheckLocalWebserver(),
    GetItemFromQueue(control, pipeline_id, downloader,
        ao_only=env.get('AO_ONLY'), large=env.get('LARGE'),
        version_check = (VERSION, pipeline_version)),
    StartHeartbeat(control),
    SetFetchDepth(),
    PreparePaths(),
    WriteInfo(),
    DownloadUrlFile(control),
    Wpull(
        wpull_args,
        accept_on_exit_code=AcceptAny(),
        env=wpull_env,
    ),
    RelabelIfAborted(control),
    CompressLogIfFailed(),
    WriteInfo(),
    MoveFiles(target_directory = os.environ["FINISHED_WARCS_DIR"]),
    StopHeartbeat(),
    MarkItemAsDone(control, EXPIRE_TIME)
)

def stop_control():
    #control.flag_logging_thread_for_termination()
    control.unregister_pipeline(pipeline_id)

pipeline.on_cleanup += stop_control

pipeline.running_status = "Running"

def status_running():
    pipeline.running_status = "Running"

pipeline.on_stop_canceled += status_running

def status_stopping():
    pipeline.running_status = "Stopping"

pipeline.on_stop_requested += status_stopping

# Activate system monitoring.
monitoring.start(pipeline, control, VERSION, downloader)

print('*' * 60)
print('Pipeline ID: %s' % pipeline_id)

if env.get('AO_ONLY'):
    print('!ao-only mode enabled; pipeline will accept jobs queued with !ao '
    '(and not jobs queued with !a or --pipeline)')

elif env.get('LARGE'):
    print('large mode enabled; pipeline will accept jobs queued with !a'
    ' --large')

elif env.get('LARGE') and env.get('AO_ONLY'):
    print('!ao-only and large modes enabled.  THIS IS PROBABLY A MISTAKE. '
    ' Pipeline will accept only jobs queued with --large or !ao.')

print('*' * 60)
print()

# vim:ts=4:sw=4:et:tw=78
