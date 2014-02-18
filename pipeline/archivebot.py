import os
import time
import random

import acceptance_heuristics
import redis_script_exec
import settings

import json
import redis


ident = os.environ['ITEM_IDENT']
rconn = redis.StrictRedis(host=os.environ['REDIS_HOST'], port=int(os.environ['REDIS_PORT']), db=os.environ['REDIS_DB'])
aborter = os.environ['ABORT_SCRIPT']
log_key = os.environ['LOG_KEY']
log_channel = os.environ['LOG_CHANNEL']

do_abort = redis_script_exec.eval_redis(os.environ['ABORT_SCRIPT'], rconn)
do_log = redis_script_exec.eval_redis(os.environ['LOG_SCRIPT'], rconn)


# Generates a log entry for ignored URLs.
def log_ignored_url(url, pattern):
  entry = dict(
    ts=time.time(),
    url=url,
    pattern=pattern,
    type='ignore'
  )

  do_log(1, ident, json.dumps(entry), log_channel, log_key)


requisite_urls = {}

def add_as_page_requisite(url):
  requisite_urls[url] = True


def accept_url(url_info, record_info, verdict, reasons):
  # Does the URL match any of the ignore patterns?
  pattern = settings.ignore_url_p(url_info['url'])

  if pattern:
    log_ignored_url(url_info['url'], pattern)
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


def abort_requested():
  return rconn.hget(ident, 'abort_requested')


# Should this result be flagged as an error?
def is_error(statcode, err):
  # 5xx: yes
  if statcode >= 500:
    return True

  # Response code zero with non-RETRFINISHED wget code: yes
  if err != 'OK':
    return True

  # Could be an error, but we don't know it as such
  return False


# Should this result be flagged as a warning?
def is_warning(statcode, err):
  return statcode >= 400 and statcode < 500


def handle_result(url_info, error_info, http_info):
  if http_info:
    # Update the traffic counters.
    rconn.hincrby(ident, 'bytes_downloaded', http_info['body']['content_size'])

  statcode = 0
  error = 'OK'

  pattern = settings.ignore_url_p(url_info['url'])

  if pattern:
    log_ignored_url(url_info['url'], pattern)
    return wpull_hook.actions.FINISH

  if http_info:
    statcode = http_info['status_code']

  if error_info:
    error = error_info['error']

  # Record the current time, URL, response code, and wget's error code.
  result = dict(
    ts=time.time(),
    url=url_info['url'],
    response_code=statcode,
    wget_code=error,
    is_error=is_error(statcode, error),
    is_warning=is_warning(statcode, error),
    type='download'
  )

  # Publish the log entry, and bump the log counter.
  do_log(1, ident, json.dumps(result), log_channel, log_key)

  # Update settings.
  if settings.update_settings(ident, rconn):
    print("Settings updated: ", settings.inspect_settings())

  # Should we abort?
  if abort_requested():
    print("Wget terminating on bot command")
    do_abort(1, ident, log_channel)

    return wpull_hook.actions.STOP

  # OK, we've finished our fetch attempt.  Now we need to figure out how much
  # we should delay.  We delay different amounts for page requisites vs.
  # non-page requisites because browsers act that way.
  sl, sm = None, None

  if requisite_urls.get(url_info['url']):
    # Yes, this will eventually free the memory needed for the key
    requisite_urls[url_info['url']] = None

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


wpull_hook.callbacks.accept_url = accept_url
wpull_hook.callbacks.handle_response = handle_response
wpull_hook.callbacks.handle_error = handle_error
wpull_hook.callbacks.finish_statistics = finish_statistics

# vim:ts=2:sw=2:et:tw=78
