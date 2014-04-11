import archivebot.control
import json
import os
import random
import time

from archivebot import acceptance_heuristics
from archivebot import shared_config
from archivebot import settings

ident = os.environ['ITEM_IDENT']
redis_url = os.environ['REDIS_URL']
log_key = os.environ['LOG_KEY']
log_channel = shared_config.log_channel()
pipeline_channel = shared_config.pipeline_channel()

control_ref = archivebot.control.Control.start(redis_url, log_channel,
    pipeline_channel)
control = control_ref.proxy()

requisite_urls = set()

def log_ignore(url, pattern):
  packet = dict(
    ts=time.time(),
    url=url,
    pattern=pattern,
    type='ignore'
  )

  control.log(packet, ident, log_key)

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

def add_as_page_requisite(url):
  requisite_urls.add(url)

def accept_url(url_info, record_info, verdict, reasons):
  url = url_info['url']

  # Does the URL match any of the ignore patterns?
  pattern = settings.ignore_url_p(url)

  if pattern:
    log_ignore(url, pattern)
    return False

  # Second-guess wget's host-spanning restrictions.
  if not verdict and acceptance_heuristics.is_span_host_filter_failed_only(reasons['filters']):
    # Is the parent a www.example.com and the child an example.com, or vice
    # versa?
    if record_info['referrer_info'] and \
    acceptance_heuristics.is_www_to_bare(record_info['referrer_info'], url_info):
      # OK, grab it after all.
      return True

    # Is this a URL of a non-hyperlinked page requisite?
    if acceptance_heuristics.is_page_requisite(record_info):
      # Yeah, grab these too.  We also flag the URL as a page requisite here
      # because we'll need to know that when we calculate the post-request
      # delay.
      add_as_page_requisite(url_info['url'])
      return True

  # If we're looking at a page requisite that didn't require verdict
  # override, flag it as a requisite.
  if verdict and acceptance_heuristics.is_page_requisite(record_info):
    add_as_page_requisite(url_info['url'])

  # If we get here, none of our exceptions apply.  Return the original
  # verdict.
  return verdict

def handle_result(url_info, error_info, http_info):
  if http_info:
    # Update the traffic counters.
    control.update_bytes_downloaded(ident, http_info['body']['content_size'])

  statcode = 0
  error = 'OK'

  pattern = settings.ignore_url_p(url_info['url'])

  if pattern:
    log_ignore(url_info['url'], pattern)
    return wpull_hook.actions.FINISH

  if http_info:
    statcode = http_info['status_code']

  if error_info:
    error = error_info['error']

  # Record the current time, URL, response code, and wget's error code.
  log_result(url_info['url'], statcode, error)

  # Update settings.
  if settings.update_settings(ident, control):
    print("Settings updated: ", settings.inspect_settings())

    # If settings changed, concurrency level may have also changed.
    clevel = settings.concurrency()
    wpull_hook.factory.get('Engine').set_concurrent(clevel)

  # Should we abort?
  if control.abort_requested(ident).get():
    print("Wget terminating on bot command")

    while True:
      try:
        control.mark_aborted(ident)
        break
      except ConnectionError:
        time.sleep(5)
        pass

    return wpull_hook.actions.STOP

  # OK, we've finished our fetch attempt.  Now we need to figure out how much
  # we should delay.  We delay different amounts for page requisites vs.
  # non-page requisites because browsers act that way.
  sl, sm = None, None

  if url_info['url'] in requisite_urls:
    # Yes, this will eventually free the memory needed for the key
    requisite_urls.remove(url_info['url'])

    sl, sm = settings.pagereq_delay_time_range()
  else:
    sl, sm = settings.delay_time_range()

  time.sleep(random.uniform(sl, sm) / 1000)

  return wpull_hook.actions.NORMAL


def handle_response(url_info, http_info):
  return handle_result(url_info, None, http_info)


def handle_error(url_info, error_info):
  return handle_result(url_info, error_info, None)


def finish_statistics(start_time, end_time, num_urls, bytes_downloaded):
  print(" ", bytes_downloaded, "bytes.")

def exit_status(exit_code):
  control.stop()

wpull_hook.callbacks.accept_url = accept_url
wpull_hook.callbacks.handle_response = handle_response
wpull_hook.callbacks.handle_error = handle_error
wpull_hook.callbacks.finish_statistics = finish_statistics
wpull_hook.callbacks.exit_status = exit_status

# vim:ts=2:sw=2:et:tw=78
