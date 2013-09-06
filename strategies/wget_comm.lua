local i = 0

wget.callbacks.httploop_result = function(url, err, http_status)
  i = i + 1
  local code = http_status.statcode

  io.stdout:write(i.."\t"..url.url.."\t"..code.."\t"..err.."\n")
  io.stdout:flush()
end

-- vim:ts=2:sw=2:et:tw=78
