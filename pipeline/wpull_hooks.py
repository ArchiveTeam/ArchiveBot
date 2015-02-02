import json
import logging
import os
import random
import time
import re
import sys

from archivebot import shared_config
from archivebot.control import Control
from archivebot.wpull import settings as mod_settings

ident = os.environ['ITEM_IDENT']
redis_url = os.environ['REDIS_URL']
log_key = os.environ['LOG_KEY']
log_channel = shared_config.log_channel()
pipeline_channel = shared_config.pipeline_channel()

control = Control(redis_url, log_channel, pipeline_channel)

settings = mod_settings.Settings()
settings_listener = mod_settings.Listener(redis_url, settings, control, ident)
settings_listener.start()

last_age = 0

logger = logging.getLogger('archivebot.pipeline.wpull_hooks')


def log_ignore(url, pattern):
  packet = dict(
    ts=time.time(),
    url=url,
    pattern=pattern,
    type='ignore'
  )

  control.log(packet, ident, log_key)


def maybe_log_ignore(url, pattern):
  if not settings.suppress_ignore_reports():
    log_ignore(url, pattern)

  logger.info('Ignore %s using pattern %s', url, pattern)


def log_result(url, statcode, error):
  packet = dict(
    ts=time.time(),
    url=url,
    response_code=statcode,
    wget_code=error,
    is_error=is_error(statcode, error),
    is_warning=is_warning(statcode, error),
    type='download'
  )

  control.log(packet, ident, log_key)


def print_log(*args):
    print(*args)
    sys.stdout.flush()
    logger.info(' '.join(str(arg) for arg in args))


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

def is_warning(statcode, err):
    '''
    Determines whether a given status code/error code combination should be
    flagged as a warning.
    '''
    return statcode >= 400 and statcode < 500


def accept_url(url_info, record_info, verdict, reasons):
  url = url_info['url']

  if url.startswith('data:'):
    # data: URLs aren't something you can grab, so drop them to avoid ignore
    # checking and ignore logging.
    return False

  # Does the URL match any of the ignore patterns?
  pattern = settings.ignore_url_p(url, record_info)

  if pattern:
    maybe_log_ignore(url, pattern)
    return False

  # If we get here, none of our ignores apply.  Return the original verdict.
  return verdict


def queued_url(url_info):
  # Increment the items queued counter.
  control.update_items_queued(1)


def dequeued_url(url_info, record_info):
  # Increment the items downloaded counter.
  control.update_items_downloaded(1)


def handle_result(url_info, record_info, error_info=None, http_info=None):
  global last_age

  if http_info and http_info['body']:
    # Update the traffic counters.
    control.update_bytes_downloaded(ident, http_info['body']['content_size'])

  error = 'OK'
  statcode = 0

  pattern = settings.ignore_url_p(url_info['url'], record_info)

  if pattern:
    maybe_log_ignore(url_info['url'], pattern)
    return wpull_hook.actions.FINISH

  if http_info:
    try:
      # HTTP
      statcode = http_info['status_code']
    except KeyError:
      try:
        # FTP
        statcode = http_info['response_code']
      except KeyError:
        pass

  if error_info:
    error = error_info['error']

  # Record the current time, URL, response code, and wget's error code.
  log_result(url_info['url'], statcode, error)

  # If settings were updated, print out a report.
  settings_age = settings.age()

  if last_age < settings_age:
    last_age = settings_age

    print_log("Settings updated: ", settings.inspect())

    # Also adjust concurrency level.
    clevel = settings.concurrency()
    wpull_hook.factory.get('Engine').set_concurrent(clevel)

  # One last thing about settings: make sure the listener is online.
  settings_listener.check()

  # Flush queued/downloaded updates.
  control.flush_item_counts(ident)

  # Should we abort?
  if settings.abort_requested():
    print_log("Wget terminating on bot command")

    while True:
      try:
        control.mark_aborted(ident)
        break
      except ConnectionError:
        time.sleep(5)
        pass

    return wpull_hook.actions.STOP

  # All clear.
  return wpull_hook.actions.NORMAL

def wait_time(seconds):
    sl, sm = settings.delay_time_range()

    return random.uniform(sl, sm) / 1000

def handle_response(url_info, record_info, http_info):
  return handle_result(url_info, record_info, http_info=http_info)


def handle_error(url_info, record_info, error_info):
  return handle_result(url_info, record_info, error_info=error_info)


def finish_statistics(start_time, end_time, num_urls, bytes_downloaded):
  print_log(" ", bytes_downloaded, "bytes.")

def exit_status(exit_code):
  settings_listener.stop()
  return exit_code

# Regular expressions for server headers go here
ICY_FIELD_PATTERN = re.compile('Icy-|Ice-|X-Audiocast-')
ICY_VALUE_PATTERN = re.compile('icecast', re.IGNORECASE)

def handle_pre_response(url_info, url_record, response_info):
  url = url_info['url']

  # Check if server version starts with ICY
  if response_info.get('version', '') == 'ICY':
    maybe_log_ignore(url, '[icy version]')

    return wpull_hook.actions.FINISH

  # Loop through all the server headers for matches
  for field, value in response_info.get('fields', []):
    if ICY_FIELD_PATTERN.match(field):
      maybe_log_ignore(url, '[icy field]')

      return wpull_hook.actions.FINISH

    if field == 'Server' and ICY_VALUE_PATTERN.match(value):
      maybe_log_ignore(url, '[icy server]')

      return wpull_hook.actions.FINISH

  # Nothing matched, allow download
  return wpull_hook.actions.NORMAL

assert 2 in wpull_hook.callbacks.AVAILABLE_VERSIONS

wpull_hook.callbacks.version = 2
wpull_hook.callbacks.accept_url = accept_url
wpull_hook.callbacks.queued_url = queued_url
wpull_hook.callbacks.dequeued_url = dequeued_url
wpull_hook.callbacks.handle_pre_response = handle_pre_response
wpull_hook.callbacks.handle_response = handle_response
wpull_hook.callbacks.handle_error = handle_error
wpull_hook.callbacks.finish_statistics = finish_statistics
wpull_hook.callbacks.exit_status = exit_status
wpull_hook.callbacks.wait_time = wait_time

# vim:ts=2:sw=2:et:tw=78
