require 'celluloid'
require 'trollop'

require File.expand_path('../job_recorder', __FILE__)
require File.expand_path('../../lib/job', __FILE__)
require File.expand_path('../../lib/log_update_listener', __FILE__)
require File.expand_path('../log_analyzer', __FILE__)
require File.expand_path('../log_trimmer', __FILE__)

opts = Trollop.options do
  opt :redis, 'URL of Redis server', :default => ENV['REDIS_URL'] || 'redis://localhost:6379/0'
  opt :log_update_channel, 'Redis pubsub channel for log updates', :default => ENV['LOG_CHANNEL'] || 'updates'
  opt :db, 'URL of CouchDB history database', :default => ENV['COUCHDB_URL'] || 'http://localhost:5984/archivebot'
  opt :db_credentials, 'Credentials for history database (USERNAME:PASSWORD)', :type => String, :default => nil
  opt :log_db, 'URL of CouchDB log database', :default => ENV['LOGDB_URL'] || 'http://localhost:5984/archivebot_logs'
  opt :log_db_credentials, 'Credentials for log database (USERNAME:PASSWORD)', :type => String, :default => nil
end

class Broadcaster < LogUpdateListener
  def on_receive(ident)
    job = ::Job.from_ident(ident, uredis)
    return unless job

    job.freeze

    Celluloid::Actor[:log_analyzer].async.process(job)
    Celluloid::Actor[:job_recorder].async.process(job)
    Celluloid::Actor[:log_trimmer].async.process(job)
  end
end

Broadcaster.supervise_as :broadcaster, opts[:redis], opts[:log_update_channel]
JobRecorder.supervise_as :job_recorder, opts[:db], opts[:db_credentials]
LogAnalyzer.supervise_as :log_analyzer
LogTrimmer.supervise_as :log_trimmer

at_exit do
  Celluloid::Actor[:broadcaster].stop
end

puts 'ArchiveBot cogs set in motion; use ^C to stop'

sleep
