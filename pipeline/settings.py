import re

# Runtime settings.  These are updated every time httploop_result is called.
settings = dict(
  age=None,
  ignore_patterns={},
  delay_min=None,
  delay_max=None,
  pagereq_delay_min=None,
  pagereq_delay_max=None
)

# If updated settings exist, updates all settings and returns true.
# Otherwise, leaves settings unchanged and returns false.
def update_settings(ident, rconn):
  age = rconn.hget(ident, 'settings_age')

  if age != settings['age']:
    results = rconn.hmget(ident,
      'delay_min', 'delay_max', 'pagereq_delay_min', 'pagereq_delay_max',
      'ignore_patterns_set_key')

    settings['delay_min'] = int(results[0]) if results[0] else None
    settings['delay_max'] = int(results[1]) if results[1] else None
    settings['pagereq_delay_min'] = int(results[2]) if results[2] else None
    settings['pagereq_delay_max'] = int(results[3]) if results[3] else None
    settings['ignore_patterns'] = rconn.smembers(results[4])
    settings['age'] = age
    return True
  else:
    return False


# If a URL matches an ignore pattern, returns the matching pattern.
# Otherwise, returns false.
def ignore_url_p(url):
  for pattern in settings['ignore_patterns']:
    if isinstance(pattern, bytes):
      pattern = pattern.decode('utf-8')

    try:
      match = re.search(pattern, url)
    except re.error as error:
      # XXX: We might not want to ignore this error
      print('Regular expression error:' + str(error) + ' on ' + pattern)
      return False

    if match:
      return pattern

  return False

# Returns a range of valid sleep times.  Sleep times are in milliseconds.
def delay_time_range():
  return settings['delay_min'] or 0, settings['delay_max'] or 0


# Returns a range of valid sleep times for page requisites.  Sleep times are
# in milliseconds.
def pagereq_delay_time_range():
  return settings['pagereq_delay_min'] or 0, settings['pagereq_delay_max'] or 0


# Returns a string describing the current settings.
def inspect_settings():
  iglen = len(settings['ignore_patterns'])
  sl, sm = delay_time_range()
  rsl, rsm = pagereq_delay_time_range()

  report = '' + str(iglen) + ' ignore patterns, '
  report += 'delay min/max: [' + str(sl) + ', ' + str(sm) + '] ms, '
  report += 'pagereq delay min/max: [' + str(rsl) + ', ' + str(rsm) + '] ms'

  return report

# vim:ts=2:sw=2:et:tw=78
