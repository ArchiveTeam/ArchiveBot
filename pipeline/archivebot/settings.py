import os
import re

from archivebot.control import ConnectionError
from . import pattern_conversion

pattern_conversion_enabled = os.environ.get('LUA_PATTERN_CONVERSION')

# Runtime settings.  These are updated every time httploop_result is called.
settings = dict(
  age=None,
  ignore_patterns={},
  delay_min=None,
  delay_max=None,
  pagereq_delay_min=None,
  pagereq_delay_max=None
)

def int_or_none(v):
  if v:
    return int(v)
  else:
    return None

# If updated settings exist, updates all settings and returns true.
# Otherwise, leaves settings unchanged and returns false.
def update_settings(ident, control):
  try:
    new_settings = control.get_settings(ident, settings['age']).get()

    if new_settings == 'same':
      return False
    else:
      settings['delay_min'] = int_or_none(new_settings['delay_min'])
      settings['delay_max'] = int_or_none(new_settings['delay_max'])
      settings['pagereq_delay_min'] = int_or_none(new_settings['pagereq_delay_min'])
      settings['pagereq_delay_max'] = int_or_none(new_settings['pagereq_delay_max'])
      settings['ignore_patterns'] = new_settings['ignore_patterns']
      settings['age'] = new_settings['age']
      return True
  except ConnectionError:
    return False

# If a URL matches an ignore pattern, returns the matching pattern.
# Otherwise, returns false.
def ignore_url_p(url):
  for pattern in settings['ignore_patterns']:
    if isinstance(pattern, bytes):
      pattern = pattern.decode('utf-8')

    if pattern_conversion_enabled:
      pattern = pattern_conversion.lua_pattern_to_regex(pattern)

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
