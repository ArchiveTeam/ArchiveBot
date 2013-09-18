local www_to_bare_p = function(url_a, url_b)
  local bare_domain = string.match(url_a.host, '^www.([^.]+.[^.]+)$')

  return url_b.host == bare_domain
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  -- Is the parent a www.example.com and the child an example.com?
  local p_to_bare = www_to_bare_p(parent, urlpos.url)

  -- Is the parent an example.com and the child a www.example.com?
  local bare_to_p = www_to_bare_p(urlpos.url, parent)

  -- If either are true and the target won't be downloaded because of
  -- span-hosts rules, override the verdict.
  --
  -- Bare domains aren't supposed to resolve to anything, but these days they
  -- are very commonly an alias for www (actually, these days, you could look
  -- at it the other way around), and we assume that any site that pulls that
  -- shit is doing the bare domain thing.
  if (p_to_bare or bare_to_p) and reason == 'DIFFERENT_HOST' then
    return true
  end

  -- Is this a URL of a non-hyperlinked page requisite?
  local is_html_link = urlpos['link_expect_html']
  local is_requisite = urlpos['link_inline_p']

  if is_html_link ~= 1 and is_requisite == 1 then
    -- Did wget decide to not download it due to span-hosts restrictions?
    if verdict == false and reason == 'DIFFERENT_HOST' then
      -- Nope, you're downloading it after all.
      return true
    end
  end

  -- Return the original verdict.
  return verdict
end

local stats = {}
local count = 0

local categorize_statcode = function(code)
  if not stats[code] then
    stats[code] = 0
  end

  count = count + 1
  stats[code] = stats[code] + 1
end

local summarize_statcodes = function()
  local ss = function(min, max)
    local sum = 0

    for code = min, max, 1 do
      local c = stats[code] or 0
      sum = sum + c
    end

    return sum
  end

  str = "1xx: "..ss(100, 199)
  str = str..", 2xx: "..ss(200, 299)
  str = str..", 3xx: "..ss(300, 399)
  str = str..", 4xx: "..ss(400, 499)
  str = str..", 5xx: "..ss(500, 599)
  str = str..", other: "..ss(600, 999)
  str = str.."."

  return str
end

local print_summary = function()
  io.stdout:write("Downloaded "..count.." URLs; ")
  io.stdout:write(summarize_statcodes())
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  categorize_statcode(http_stat.statcode)

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
