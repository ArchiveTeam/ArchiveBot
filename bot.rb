require 'cinch'
require 'redis'
require 'trollop'
require 'uri'

require File.expand_path('../brain', __FILE__)

opts = Trollop.options do
  opt :server, 'IRC server, expressed as a URI (irc://SERVER:PORT or //SERVER:PORT)', :type => String
  opt :nick, 'Nick to use', :default => 'ArchiveBot'
  opt :channels, 'Comma-separated list of channels', :type => String
  opt :schemes, 'Comma-separated list of acceptable URI schemes', :default => 'http,https'
end

redis = Redis.new(:url => 'redis://localhost:6379/0')

%w(server nick channels).each do |opt|
  Trollop.die "#{opt} is required" unless opts[opt.to_sym]
end

schemes = opts[:schemes].split(',').map(&:strip)
channels = opts[:channels].split(',').map(&:strip)
uri = URI.parse(opts[:server])

bot = Cinch::Bot.new do
  configure do |c|
    c.server = uri.host
    c.port = uri.port
    c.nick = opts[:nick]
    c.channels = channels
  end

  brain = Brain.new(schemes, redis)

  on :message, /\A\!archive (.+)\Z/ do |m, param|
    brain.request_archive(m, param)
  end

  on :message, /\A\!status\Z/ do |m|
    brain.request_summary(m)
  end

  on :message, /\A!status ([0-9a-z]+)\Z/ do |m, ident|
    brain.request_status(m, ident)
  end

  on :message, /\A!abort ([0-9a-z]+)\Z/ do |m, ident|
    brain.initiate_abort(m, ident)
  end
end

bot.start
