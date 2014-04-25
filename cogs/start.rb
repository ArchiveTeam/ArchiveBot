require 'celluloid'
require 'trollop'
require 'uri'

require File.expand_path('../ignore_pattern_updater', __FILE__)
require File.expand_path('../job_recorder', __FILE__)
require File.expand_path('../../lib/job', __FILE__)
require File.expand_path('../../lib/redis_subscriber', __FILE__)
require File.expand_path('../../lib/shared_config', __FILE__)
require File.expand_path('../log_analyzer', __FILE__)
require File.expand_path('../log_trimmer', __FILE__)
require File.expand_path('../reaper', __FILE__)
require File.expand_path('../twitter_concierge', __FILE__)
require File.expand_path('../twitter_tweeter', __FILE__)
require File.expand_path('../twitter_listener', __FILE__)
require File.expand_path('../archive_finder', __FILE__)

opts = Trollop.options do
  opt :redis, 'URL of Redis server', :default => ENV['REDIS_URL'] || 'redis://localhost:6379/0'
  opt :db, 'URL of CouchDB history database', :default => ENV['COUCHDB_URL'] || 'http://localhost:5984/archivebot'
  opt :db_credentials, 'Credentials for history database (USERNAME:PASSWORD)', :type => String, :default => nil
  opt :log_db, 'URL of CouchDB log database', :default => ENV['LOGDB_URL'] || 'http://localhost:5984/archivebot_logs'
  opt :log_db_credentials, 'Credentials for log database (USERNAME:PASSWORD)', :type => String, :default => nil
  opt :twitter_config, 'Filename containing Twitter key config', :type => String, :default => nil
end

class Broadcaster < RedisSubscriber
  def on_receive(ident)
    job = ::Job.from_ident(ident, uredis)
    return unless job

    job.freeze

    Celluloid::Actor[:log_analyzer].async.process(job)
    Celluloid::Actor[:job_recorder].async.process(job)
    Celluloid::Actor[:log_trimmer].async.process(job)
    Celluloid::Actor[:twitter_tweeter].async.process(job)
  end
end

db_uri = URI(opts[:db])

JobRecorder.supervise_as :job_recorder, db_uri, opts[:db_credentials]
LogAnalyzer.supervise_as :log_analyzer
LogTrimmer.supervise_as :log_trimmer, URI(opts[:log_db]),
  opts[:log_db_credentials]

Reaper.supervise_as :reaper, opts[:redis]
TwitterConcierge.supervise_as :twitter_concierge
TwitterTweeter.supervise_as :twitter_tweeter, opts[:redis], opts[:twitter_config]
TwitterListener.supervise_as :twitter_listener, :twitter_concierge, db_uri,
  opts[:db_credentials], opts[:twitter_config]
ArchiveFinder.supervise_as :archive_finder, opts[:redis], db_uri,
  opts[:db_credentials]

ignore_patterns_path = File.expand_path('../../db/ignore_patterns', __FILE__)

IgnorePatternUpdater.supervise_as :ignore_pattern_updater,
  ignore_patterns_path, db_uri, opts[:db_credentials]

# This should be started after all actors it references have started, which is
# why it's the last actor to start up.
Broadcaster.supervise_as :broadcaster, opts[:redis], SharedConfig.log_channel

at_exit do
  Celluloid::Actor[:broadcaster].stop
  Celluloid::Actor[:ignore_pattern_updater].stop
  Celluloid::Actor[:archive_finder].stop
end

trap('INT') do
  exit 0
end

puts 'ArchiveBot cogs set in motion; use ^C to stop'

sleep
