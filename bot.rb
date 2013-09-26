require 'cinch'
require 'redis'
require 'trollop'
require 'uri'

require File.expand_path('../brain', __FILE__)
require File.expand_path('../log_analyzer', __FILE__)
require File.expand_path('../job_recorder', __FILE__)

opts = Trollop.options do
  opt :server, 'IRC server, expressed as a URI (irc://SERVER:PORT or //SERVER:PORT)', :type => String
  opt :nick, 'Nick to use', :default => 'ArchiveBot'
  opt :channels, 'Comma-separated list of channels', :type => String
  opt :schemes, 'Comma-separated list of acceptable URI schemes', :default => 'http,https'
  opt :redis, 'URL of Redis server', :default => ENV['REDIS_URL'] || 'redis://localhost:6379/0'
  opt :db, 'URL of CouchDB history database', :default => ENV['COUCHDB_URL'] || 'http://localhost:5984/archivebot_history'
  opt :db_credentials, 'Credentials for history database (USERNAME:PASSWORD)', :type => String, :default => nil
  opt :log_update_channel, 'Redis pubsub channel for log updates', :default => ENV['LOG_CHANNEL'] || 'updates'
end

redis = Redis.new(:url => opts[:redis])

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

  on :message, /\A!archiveonly (.+)\Z/ do |m, param|
    brain.request_archive(m, param, :shallow)
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

LogAnalyzer.supervise_as :log_analyzer, opts[:redis], opts[:log_update_channel]
JobRecorder.supervise_as :job_recorder, opts[:redis],
  opts[:log_update_channel], opts[:db], opts[:db_credentials]

at_exit do
  Celluloid::Actor[:log_analyzer].stop
  Celluloid::Actor[:job_recorder].stop
end

bot.start
