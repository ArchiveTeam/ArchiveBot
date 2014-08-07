import json
import os
import random
import time

from archivebot import shared_config
from archivebot.control import Control
from archivebot.wpull import settings as mod_settings
from pykka.registry import ActorRegistry

ident = os.environ['ITEM_IDENT']
redis_url = os.environ['REDIS_URL']
log_key = os.environ['LOG_KEY']
log_channel = shared_config.log_channel()
pipeline_channel = shared_config.pipeline_channel()

settings_ref = mod_settings.Settings.start()
settings = settings_ref.proxy()

control_ref = Control.start(redis_url, log_channel, pipeline_channel)
control = control_ref.proxy()

settings_listener = mod_settings.Listener(redis_url, settings, control, ident)
settings_listener.start()

last_age = 0

def log_ignore(url, pattern):
  packet = dict(
    ts=time.time(),
    url=url,
    pattern=pattern,
    type='ignore'
  )

  control.log(packet, ident, log_key).get()

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

  control.log(packet, ident, log_key).get()

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

  # Does the URL match any of the ignore patterns?
  pattern = settings.ignore_url_p(url).get()

  if pattern:
    if not settings.suppress_ignore_reports().get():
      log_ignore(url, pattern)
    return False

  # If we get here, none of our ignores apply.  Return the original verdict.
  return verdict

def handle_result(url_info, record_info, error_info=None, http_info=None):
  global last_age

  if http_info:
    # Update the traffic counters.
    control.update_bytes_downloaded(ident, http_info['body']['content_size']).get()

  statcode = 0
  error = 'OK'

  pattern = settings.ignore_url_p(url_info['url']).get()

  if pattern:
    log_ignore(url_info['url'], pattern)
    return wpull_hook.actions.FINISH

  if http_info:
    statcode = http_info['status_code']

  if error_info:
    error = error_info['error']

  # Record the current time, URL, response code, and wget's error code.
  log_result(url_info['url'], statcode, error)

  # If settings were updated, print out a report.
  settings_age = settings.age().get()

  if last_age < settings_age:
    last_age = settings_age

    print("Settings updated: ", settings.inspect().get())

    # Also adjust concurrency level.
    clevel = settings.concurrency().get()
    wpull_hook.factory.get('Engine').set_concurrent(clevel)

  # One last thing about settings: make sure the listener is online.
  settings_listener.check()

  # Should we abort?
  if settings.abort_requested().get():
    print("Wget terminating on bot command")

    while True:
      try:
        control.mark_aborted(ident).get()
        break
      except ConnectionError:
        time.sleep(5)
        pass

    return wpull_hook.actions.STOP

  # All clear.
  return wpull_hook.actions.NORMAL

def wait_time(seconds):
    sl, sm = settings.delay_time_range().get()

    return random.uniform(sl, sm) / 1000

def handle_response(url_info, record_info, http_info):
  return handle_result(url_info, record_info, http_info=http_info)


def handle_error(url_info, record_info, error_info):
  return handle_result(url_info, record_info, error_info=error_info)


def finish_statistics(start_time, end_time, num_urls, bytes_downloaded):
  print(" ", bytes_downloaded, "bytes.")

def exit_status(exit_code):
  settings_listener.stop()
  ActorRegistry.stop_all()
  return exit_code


assert 2 in wpull_hook.callbacks.AVAILABLE_VERSIONS

wpull_hook.callbacks.version = 2
wpull_hook.callbacks.accept_url = accept_url
wpull_hook.callbacks.handle_response = handle_response
wpull_hook.callbacks.handle_error = handle_error
wpull_hook.callbacks.finish_statistics = finish_statistics
wpull_hook.callbacks.exit_status = exit_status
wpull_hook.callbacks.wait_time = wait_time

# vim:ts=2:sw=2:et:tw=78
