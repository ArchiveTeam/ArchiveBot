require 'sinatra'

get '/:sec/' do |sec|
  "<html><head><title>What</title><body><a href='/#{sec}/1.html'>1</a></body></html>"
end

get /([a-z]+)\/(\d+)\.html/ do |sec, id|
  intid = id.to_i

  if intid < 20000
    "<html><head><title>What</title><body><a href='/#{sec}/#{intid+1}.html'>#{intid+1}</a></body></html>"
  else
    status 404
    ""
  end
end
