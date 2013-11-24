require 'celluloid'
require 'trollop'

require File.expand_path('../log_analyzer', __FILE__)
require File.expand_path('../log_trimmer', __FILE__)
require File.expand_path('../job_recorder', __FILE__)

opts = Trollop.options do
  opt :redis, 'URL of Redis server', :default => ENV['REDIS_URL'] || 'redis://localhost:6379/0'
  opt :log_update_channel, 'Redis pubsub channel for log updates', :default => ENV['LOG_CHANNEL'] || 'updates'
  opt :db, 'URL of CouchDB history database', :default => ENV['COUCHDB_URL'] || 'http://localhost:5984/archivebot'
  opt :db_credentials, 'Credentials for history database (USERNAME:PASSWORD)', :type => String, :default => nil
  opt :log_db, 'URL of CouchDB log database', :default => ENV['LOGDB_URL'] || 'http://localhost:5984/archivebot_logs'
  opt :log_db_credentials, 'Credentials for log database (USERNAME:PASSWORD)', :type => String, :default => nil
end

LogAnalyzer.supervise_as :log_analyzer, opts[:redis], opts[:log_update_channel]
LogTrimmer.supervise_as :log_trimmer, opts[:redis], opts[:log_update_channel],
  opts[:log_db], opts[:log_db_credentials]
JobRecorder.supervise_as :job_recorder, opts[:redis],
  opts[:log_update_channel], opts[:db], opts[:db_credentials]

at_exit do
  Celluloid::Actor[:log_analyzer].stop
  Celluloid::Actor[:job_recorder].stop
  Celluloid::Actor[:log_trimmer].stop
end

sleep
