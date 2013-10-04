dofile("redis_script_exec.lua")
dofile("wget_behaviors/acceptance_heuristics.lua")

require('socket')

local json = require('json')
local redis = require('vendor/redis-lua/src/redis')
local ident = os.getenv('ITEM_IDENT')
local rconn = redis.connect(os.getenv('REDIS_HOST'), os.getenv('REDIS_PORT'))
local aborter = os.getenv('ABORT_SCRIPT')
local log_key = os.getenv('LOG_KEY')
local log_channel = os.getenv('LOG_CHANNEL')

local do_abort = eval_redis(os.getenv('ABORT_SCRIPT'), rconn)
local do_log = eval_redis(os.getenv('LOG_SCRIPT'), rconn)

rconn:select(os.getenv('REDIS_DB'))

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  -- Second-guess wget's host-spanning restrictions.
  if not verdict and reason == 'DIFFERENT_HOST' then
    -- Is the parent a www.example.com and the child an example.com, or vice
    -- versa?
    if is_www_to_bare(parent, urlpos.url) then
      -- OK, grab it after all.
      return true
    end

    -- Is this a URL of a non-hyperlinked page requisite?
    if is_page_requisite(urlpos) then
      -- Yeah, grab these too.
      return true
    end
  end

  -- Return the original verdict.
  return verdict
end

local abort_requested = function()
  return rconn:hget(ident, 'abort_requested')
end

-- Should this result be flagged as an error?
local is_error = function(statcode, err)
  -- 5xx: yes
  if statcode >= 500 then
    return true
  end

  -- Response code zero with non-RETRFINISHED wget code: yes
  if statcode == 0 and err ~= 'RETRFINISHED' then
    return true
  end

  -- Could be an error, but we don't know it as such
  return false
end

-- Should this result be flagged as a warning?
local is_warning = function(statcode, err)
  return statcode >= 400 and statcode < 500
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  -- Update the traffic counters.
  rconn:hincrby(ident, 'bytes_downloaded', http_stat.rd_size)

  local statcode = http_stat['statcode']

  -- Record the current time, URL, response code, and wget's error code.
  local result = {
    ts = os.date('%c'),
    url = url['url'],
    response_code = statcode,
    wget_code = err,
    is_error = is_error(statcode, err),
    is_warning = is_warning(statcode, err),
    msg_type = 'download'
  }

  -- Publish the log entry, and bump the log counter.
  do_log(1, ident, json.encode(result), log_channel)

  -- Should we abort?
  if abort_requested() then
    io.stdout:write("Wget terminating on bot command")
    do_abort(1, ident, 60, log_channel, os.time())

    return wget.actions.ABORT
  end

  return wget.actions.NOTHING
end

wget.callbacks.finish = function(start_time, end_time, wall_time, numurls, total_downloaded_bytes, total_download_time)
  io.stdout:write("  ")
  io.stdout:write(total_downloaded_bytes.." bytes.")
  io.stdout:write("\n")
  io.stdout:flush()
end

-- vim:ts=2:sw=2:et:tw=78
