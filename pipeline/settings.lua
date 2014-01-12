-- Runtime settings.  These are updated every time httploop_result is called.
local settings = {
  age = nil,
  ignore_patterns = {},
  sleep_min = nil,
  sleep_max = nil
}

-- If updated settings exist, updates all settings and returns true.
-- Otherwise, leaves settings unchanged and returns false.
archivebot.update_settings = function(ident, rconn)
  local age = rconn:hget(ident, 'settings_age')

  if age ~= settings.age then
    local results = rconn:hmget(ident, 'sleep_min', 'sleep_max',
      'ignore_patterns_set_key')
    local sl = results[1]
    local sm = results[2]
    local igkey = results[3]

    settings.ignore_patterns = rconn:smembers(igkey)
    settings.sleep_min = sl
    settings.sleep_max = sm
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
archivebot.sleep_time_range = function()
  return settings.sleep_min or 0, settings.sleep_max or 0
end

-- Returns a string describing the current settings.
archivebot.inspect_settings = function()
  local iglen = table.getn(settings.ignore_patterns)
  local sl, sm = archivebot.sleep_time_range()

  return ""..iglen.." ignore patterns, sleep min/max: ["..sl..", "..sm.."] ms"
end

-- vim:ts=2:sw=2:et:tw=78
