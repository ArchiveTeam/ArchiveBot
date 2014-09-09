require 'sinatra'

str = lambda do |sec, intid|
    %Q{
<!doctype html>
<html>
<head><title>What</title></head>
<body>
  <a href="/#{sec}/#{intid+1}.html">#{intid+1}</a>
  <a href="/#{sec}/0/#{intid+1}.html">#{intid+1}</a>
  <a href="/#{sec}/1/#{intid+1}.html">#{intid+1}</a>
  <a href="/#{sec}/2/#{intid+1}.html">#{intid+1}</a>
  <a href="/#{sec}/3/#{intid+1}.html">#{intid+1}</a>
  <a href="/#{sec}/4/#{intid+1}.html">#{intid+1}</a>
</body>
</html>
    }.strip
end

get '/:sec/' do |sec|
  str[sec, 0]
end

get /([a-z0-9]+)\/(\d+)\.html/ do |sec, id|
  intid = id.to_i

  if intid < 500
    str[sec, intid]
  else
    status 404
    ""
  end
end

get /([a-z0-9]+)\/\d+\/(\d+)\.html/ do |sec, id|
  intid = id.to_i

  if intid < 1000
    str[sec, intid]
  else
    status 404
    ""
  end
end
