require 'irb'
require 'redis'
require 'trollop'

require File.expand_path('../../lib/job', __FILE__)

opts = Trollop.options do
  opt :redis, 'URL of Redis server', :default => ENV['REDIS_URL'] || 'redis://localhost:6379/0'
end

$redis = Redis.new(:url => opts[:redis])

def job(ident)
  Job.from_ident(ident, $redis)
end

def keys
  $redis.keys
end

IRB.start
