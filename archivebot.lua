dofile("wget_behaviors/acceptance_heuristics.lua")
dofile("wget_behaviors/url_counting.lua")

require('socket')

local redis = require('vendor/redis-lua/src/redis')
local ident = os.getenv('ITEM_IDENT')
local rconn = redis.connect(os.getenv('REDIS_HOST'), os.getenv('REDIS_PORT'))
local aborter = os.getenv('ABORT_SCRIPT')
local error_list = os.getenv('ERROR_LIST')

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

local aborted = function()
  return rconn:hget(ident, 'aborted')
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  -- Categorize what we just downloaded and update the traffic counters.
  categorize_statcode(http_stat.statcode)
  rconn:hincrby(ident, 'bytes_downloaded', http_stat.rd_size)

  -- If there was an error, record the URL and the error code.
  if err ~= "RETRFINISHED" then
    rconn:lpush(error_list, '{"url":"'..url['url']..'","code":"'..err..'"}')
  end

  -- Should we abort?
  if aborted() then
    io.stdout:write("Wget terminating on bot command")
    rconn:eval(aborter, 1, ident, 60)

    return wget.actions.ABORT
  end

  -- Should we print a summary line?
  if count % 50 == 0 then
    print_summary()
    io.stdout:write("\n")
    io.stdout:flush()
  end

  return wget.actions.NOTHING
end

wget.callbacks.finish = function(start_time, end_time, wall_time, numurls, total_downloaded_bytes, total_download_time)
  print_summary()
  io.stdout:write("  ")
  io.stdout:write(total_downloaded_bytes.." bytes.")
  io.stdout:write("\n")
  io.stdout:flush()
end

-- vim:ts=2:sw=2:et:tw=78
