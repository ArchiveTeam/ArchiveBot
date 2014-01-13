-- Runtime settings.  These are updated every time httploop_result is called.
local settings = {
  age = nil,
  ignore_patterns = {},
  delay_min = nil,
  delay_max = nil,
  pagereq_delay_min = nil,
  pagereq_delay_max = nil
}

-- If updated settings exist, updates all settings and returns true.
-- Otherwise, leaves settings unchanged and returns false.
archivebot.update_settings = function(ident, rconn)
  local age = rconn:hget(ident, 'settings_age')

  if age ~= settings.age then
    local results = rconn:hmget(ident,
      'delay_min', 'delay_max', 'pagereq_delay_min', 'pagereq_delay_max',
      'ignore_patterns_set_key')

    settings.delay_min = results[1]
    settings.delay_max = results[2]
    settings.pagereq_delay_min = results[3]
    settings.pagereq_delay_max = results[4]
    settings.ignore_patterns = rconn:smembers(results[5])
    settings.age = age
    return true
  else
    return false
  end
end

-- If a URL matches an ignore pattern, returns the matching pattern.
-- Otherwise, returns false.
archivebot.ignore_url_p = function(url)
  for i, pattern in ipairs(settings.ignore_patterns) do
   if string.find(url, pattern) then
     return pattern
   end
 end

 return false
end

-- Returns a range of valid sleep times.  Sleep times are in milliseconds.
archivebot.delay_time_range = function()
  return settings.delay_min or 0, settings.delay_max or 0
end

-- Returns a range of valid sleep times for page requisites.  Sleep times are
-- in milliseconds.
archivebot.pagereq_delay_time_range = function()
  return settings.pagereq_delay_min or 0, settings.pagereq_delay_max or 0
end

-- Returns a string describing the current settings.
archivebot.inspect_settings = function()
  local iglen = table.getn(settings.ignore_patterns)
  local sl, sm = archivebot.delay_time_range()
  local rsl, rsm = archivebot.pagereq_delay_time_range()

  local report = ''..iglen..' ignore patterns, '
  report = report..'delay min/max: ['..sl..', '..sm..'] ms, '
  report = report..'pagereq delay min/max: ['..rsl..', '..rsm..'] ms'

  return report
end

-- vim:ts=2:sw=2:et:tw=78
