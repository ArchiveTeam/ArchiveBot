require 'cinch'
require 'redis-namespace'
require 'trollop'
require 'uri'

require File.expand_path('../brain', __FILE__)

opts = Trollop.options do
  opt :server, 'IRC server, expressed as a URI (irc://SERVER:PORT or //SERVER:PORT)', :type => String
  opt :nick, 'Nick to use', :default => 'ArchiveBot'
  opt :channels, 'Comma-separated list of channels', :type => String
  opt :schemes, 'Comma-separated list of acceptable URI schemes', :default => 'http,https'
  opt :redis, 'Redis server for job tracking', :default => 'redis://localhost:6379'
  opt :redis_namespace, 'Redis namespace for job tracking', :default => 'archivebot'
end

%w(server nick channels).each do |opt|
  Trollop.die "#{opt} is required" unless opts[opt.to_sym]
end

schemes = opts[:schemes].split(',').map(&:strip)
channels = opts[:channels].split(',').map(&:strip)
uri = URI.parse(opts[:server])
rconn = Redis.new(:url => opts[:redis])
redis = Redis::Namespace.new(opts[:redis_namespace], :redis => rconn)

bot = Cinch::Bot.new do
  configure do |c|
    c.server = uri.host
    c.port = uri.port
    c.nick = opts[:nick]
    c.channels = channels
  end

  brain = Brain.new(redis, schemes)

  on :message, /\A\!archive (.+)\Z/ do |m, param|
    brain.request_archive(m, param)
  end
end

bot.start
