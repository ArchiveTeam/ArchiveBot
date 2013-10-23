require 'cinch'
require 'redis'
require 'trollop'
require 'uri'

require File.expand_path('../brain', __FILE__)
require File.expand_path('../command_patterns', __FILE__)
require File.expand_path('../../lib/history_db', __FILE__)

opts = Trollop.options do
  opt :server, 'IRC server, expressed as a URI (irc://SERVER:PORT or //SERVER:PORT)', :type => String
  opt :nick, 'Nick to use', :default => 'ArchiveBot'
  opt :channels, 'Comma-separated list of channels', :type => String
  opt :schemes, 'Comma-separated list of acceptable URI schemes', :default => 'http,https'
  opt :redis, 'URL of Redis server', :default => ENV['REDIS_URL'] || 'redis://localhost:6379/0'
  opt :db, 'URL of CouchDB history database', :default => ENV['COUCHDB_URL'] || 'http://localhost:5984/archivebot_history'
  opt :db_credentials, 'Credentials for history database (USERNAME:PASSWORD)', :type => String, :default => nil
end

redis = Redis.new(:url => opts[:redis])

%w(server nick channels).each do |opt|
  Trollop.die "#{opt} is required" unless opts[opt.to_sym]
end

schemes = opts[:schemes].split(',').map(&:strip)
channels = opts[:channels].split(',').map(&:strip)
uri = URI.parse(opts[:server])

ident_regex = /[0-9a-z]+/

bot = Cinch::Bot.new do
  configure do |c|
    c.server = uri.host
    c.port = uri.port
    c.nick = opts[:nick]
    c.channels = channels
  end

  history_db = HistoryDb.new(URI(opts[:db]), opts[:db_credentials])
  brain = Brain.new(schemes, redis, history_db)

  on :message, CommandPatterns::ARCHIVE do |m, url, params|
    brain.request_archive(m, url)
  end

  on :message, CommandPatterns::ARCHIVEONLY do |m, url, params|
    brain.request_archive(m, url, :shallow)
  end

  on :message, /\A\!status\Z/ do |m|
    brain.request_summary(m)
  end

  on :message, /\A!status (#{ident_regex})\Z/ do |m, ident|
    brain.request_status_by_ident(m, ident)
  end

  on :message, /\A!status (#{brain.url_pattern})\Z/ do |m, url|
    brain.request_status_by_url(m, url)
  end

  on :message, /\A!ig(?:nore)? (#{ident_regex}) (.+)/ do |m, ident, pattern|
    brain.add_ignore_pattern(m, ident, pattern)
  end

  on :message, /\A!unig(?:nore)? (#{ident_regex}) (.+)/ do |m, ident, pattern|
    brain.remove_ignore_pattern(m, ident, pattern)
  end

  on :message, /\A!abort (#{ident_regex})\Z/ do |m, ident|
    brain.initiate_abort(m, ident)
  end
end

bot.start
