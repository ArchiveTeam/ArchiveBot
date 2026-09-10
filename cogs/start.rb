require 'celluloid'
require 'trollop'
require 'uri'

require File.expand_path('../ignore_pattern_updater', __FILE__)
require File.expand_path('../user_agent_updater', __FILE__)
require File.expand_path('../../lib/job', __FILE__)
require File.expand_path('../../lib/redis_subscriber', __FILE__)
require File.expand_path('../../lib/shared_config', __FILE__)
require File.expand_path('../reaper', __FILE__)

opts = Trollop.options do
  opt :redis, 'URL of Redis server', :default => ENV['REDIS_URL'] || 'redis://localhost:6379/0'
  opt :db, 'URL of CouchDB history database', :default => ENV['COUCHDB_URL'] || 'http://localhost:5984/archivebot'
  opt :db_credentials, 'Credentials for history database (USERNAME:PASSWORD)', :type => String, :default => nil
  opt :log_db, 'URL of CouchDB log database', :default => ENV['LOGDB_URL'] || 'http://localhost:5984/archivebot_logs'
  opt :log_db_credentials, 'Credentials for log database (USERNAME:PASSWORD)', :type => String, :default => nil
  opt :twitter_config, 'Deprecated option', :type => String, :default => nil # if not used anymore, can be removed
end

class Broadcaster < RedisSubscriber
  def on_receive(ident)
    job = ::Job.from_ident(ident, uredis)
    return unless job

    job.freeze
  end
end

db_uri = URI(opts[:db])

Reaper.supervise_as :reaper, opts[:redis]

ignore_patterns_path = File.expand_path('../../db/ignore_patterns', __FILE__)

IgnorePatternUpdater.supervise_as :ignore_pattern_updater,
  ignore_patterns_path, db_uri, opts[:db_credentials]

user_agents_path = File.expand_path('../../db/user_agents', __FILE__)

UserAgentUpdater.supervise_as :user_agent_updater,
  user_agents_path, db_uri, opts[:db_credentials]


if opts[:twitter_config]
  STDERR.puts "twitter_config option is now deprecated"
end

at_exit do
  Celluloid::Actor[:ignore_pattern_updater].stop
  Celluloid::Actor[:user_agent_updater].stop
end

trap('INT') do
  exit 0
end

puts 'ArchiveBot cogs set in motion; use ^C to stop'

sleep
