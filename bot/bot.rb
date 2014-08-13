require 'cinch'
require 'redis'
require 'trollop'
require 'uri'

require File.expand_path('../brain', __FILE__)
require File.expand_path('../command_patterns', __FILE__)
require File.expand_path('../finish_notifier', __FILE__)
require File.expand_path('../../lib/couchdb', __FILE__)

opts = Trollop.options do
  opt :server, 'IRC server, expressed as a URI (irc://SERVER:PORT or ircs://SERVER:PORT for SSL)', :type => String
  opt :nick, 'Nick to use', :default => 'ArchiveBot'
  opt :channels, 'Comma-separated list of channels', :type => String
  opt :schemes, 'Comma-separated list of acceptable URI schemes', :default => 'http,https'
  opt :redis, 'URL of Redis server', :default => ENV['REDIS_URL'] || 'redis://localhost:6379/0'
  opt :db, 'URL of CouchDB database', :default => ENV['COUCHDB_URL'] || 'http://localhost:5984/archivebot'
  opt :db_credentials, 'Credentials for CouchDB database (USERNAME:PASSWORD)', :type => String, :default => nil
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
    c.plugins.plugins = [FinishNotifier]
    c.plugins.options[FinishNotifier] = {
      redis: redis
    }

    if uri.scheme == 'ircs'
      c.ssl.use = true
    end
  end

  couchdb = Couchdb.new(URI(opts[:db]), opts[:db_credentials])
  brain = Brain.new(schemes, redis, couchdb)

  on :message, CommandPatterns::ARCHIVE do |m, target, params|
    brain.request_archive(m, target, params)
  end

  on :message, CommandPatterns::ARCHIVEONLY do |m, target, params|
    brain.request_archive(m, target, params, :shallow)
  end

  on :message, CommandPatterns::ARCHIVEONLY_FILE do |m, target, params|
    brain.request_archive(m, target, params, :shallow, true)
  end

  on :message, /\A\!status\Z/ do |m|
    brain.request_summary(m)
  end

  on :message, /\A!status (#{CommandPatterns::IDENT})\Z/ do |m, ident|
    brain.find_job(ident, m) { |j| brain.request_status(m, j) }
  end

  on :message, /\A!status (#{brain.url_pattern})\Z/ do |m, url|
    brain.request_status_by_url(m, url)
  end

  on :message, /\A!ig(?:nore)? (#{CommandPatterns::IDENT}) (.+)/ do |m, ident, pattern|
    brain.find_job(ident, m) { |j| brain.add_ignore_pattern(m, j, pattern) }
  end

  on :message, /\A!unig(?:nore)? (#{CommandPatterns::IDENT}) (.+)/ do |m, ident, pattern|
    brain.find_job(ident, m) { |j| brain.remove_ignore_pattern(m, j, pattern) }
  end

  on :message, /\A!ig(?:nore)?set (#{CommandPatterns::IDENT}) (.+)/ do |m, ident, sets|
    brain.find_job(ident, m) { |j| brain.add_ignore_sets(m, j, sets) }
  end

  on :message, /\A!expire (#{CommandPatterns::IDENT})\Z/ do |m, ident|
    brain.find_job(ident, m) { |j| brain.expire(m, j) }
  end

  on :message, CommandPatterns::SET_DELAY do |m, ident, min, max|
    brain.find_job(ident, m) { |j| brain.set_delay(j, min, max, m) }
  end

  on :message, CommandPatterns::SET_CONCURRENCY do |m, ident, level|
    brain.find_job(ident, m) { |j| brain.set_concurrency(j, level, m) }
  end

  on :message, /\A!yahoo (#{CommandPatterns::IDENT})\Z/ do |m, ident|
    brain.find_job(ident, m) { |j| brain.yahoo(j, m) }
  end

  on :message, /\A!abort (#{CommandPatterns::IDENT})\Z/ do |m, ident|
    brain.find_job(ident, m) { |j| brain.initiate_abort(m, j) }
  end

  on :message, /\A(?:!igrep|!ignorereports) (#{CommandPatterns::IDENT}) (on|off)\Z/ do |m, ident, mode|
    brain.find_job(ident, m) do |j|
      brain.toggle_ignores(m, j, mode == 'on' ? true : false)
    end
  end

  on :message, /\A!pending\Z/ do |m|
    brain.show_pending(m)
  end
end

bot.start
