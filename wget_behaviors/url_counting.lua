local stats = {}
local b1xx = {100, 200}
local b2xx = {200, 300}
local b3xx = {300, 400}
local b4xx = {400, 500}
local b5xx = {500, 600}

count = 0

local report = function(buckets)
  local str = "1xx: "..buckets[b1xx].."; "
  str = str.."2xx: "..buckets[b2xx].."; "
  str = str.."3xx: "..buckets[b3xx].."; "
  str = str.."4xx: "..buckets[b4xx].."; "
  str = str.."5xx: "..buckets[b5xx].."; "
  str = str.."other: "..buckets['other']..". "

  return str
end

local summarize_statcodes = function()
  local buckets = {
    [b1xx] = 0,
    [b2xx] = 0,
    [b3xx] = 0,
    [b4xx] = 0,
    [b5xx] = 0,
    other  = 0
  }

  for code, count in pairs(stats) do
    local set = false

    for range, value in pairs(buckets) do
      if range ~= 'other' and (code >= range[1] and code < range[2]) then
        buckets[range] = buckets[range] + count
        set = true
        break
      end
    end

    if not set then
      buckets['other'] = buckets['other'] + count
    end
  end

  return report(buckets)
end

categorize_statcode = function(code)
  if not stats[code] then
    stats[code] = 0
  end

  count = count + 1
  stats[code] = stats[code] + 1
end

print_summary = function()
  io.stdout:write("Downloaded "..count.." URLs; ")
  io.stdout:write(summarize_statcodes())
end

-- vim:ts=2:sw=2:et:tw=78
