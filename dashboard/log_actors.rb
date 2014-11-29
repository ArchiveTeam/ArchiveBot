require 'celluloid'
require 'celluloid/autostart'
require 'reel'

require File.expand_path('../../lib/job', __FILE__)
require File.expand_path('../../lib/redis_subscriber', __FILE__)
require File.expand_path('../../lib/shared_config', __FILE__)
require File.expand_path('../messages', __FILE__)

UPDATE_TOPIC = SharedConfig.log_channel.freeze

# Each WebSocket listener turns into an actor.
class LogClient
  include Celluloid
  include Celluloid::Notifications

  def initialize(socket)
    @socket = socket

    subscribe(UPDATE_TOPIC, :relay)
  end

  def relay(pattern, message)
    if pattern == UPDATE_TOPIC
      begin
        @socket << message
      rescue
        terminate
      end
    end
  end
end
