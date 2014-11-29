require File.expand_path('../../archive_bot', __FILE__)

require 'redis'

module ArchiveBot
  module Redis
    ##
    # Constructs a ::Redis object.  The default Redis URL is read from the
    # REDIS_URL environment variable.
    def make_redis(url = ENV['REDIS_URL'])
      abort 'Redis URL not specified (is REDIS_URL set?)' unless url

      ::Redis.new(url: url, driver: :hiredis)
    end
    
    ##
    # Returns the Redis pubsub channel where job status notifications will be
    # sent.
    def updates_channel
      ENV['UPDATES_CHANNEL'] or abort 'Updates pubsub channel not specified (is UPDATES_CHANNEL set?)'
    end
  end
end
