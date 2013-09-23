require 'celluloid'
require 'celluloid/autostart'
require 'reel'

require File.expand_path('../../job', __FILE__)
require File.expand_path('../../log_update_listener', __FILE__)
require File.expand_path('../packet', __FILE__)

UPDATE_TOPIC = 'updates'.freeze

# Receives messages from the log update pubsub channel, fetches log messages
# and relevant data, and sends said data out to all connected clients.
class LogReceiver < LogUpdateListener
  include Celluloid::Notifications

  def on_receive(ident)
    j = ::Job.from_ident(ident, uredis)

    if j
      entries = j.read_new_entries
      packet = Packet.new(j, entries)
      publish(UPDATE_TOPIC, packet)
    end
  end
end

# Each WebSocket listener turns into an actor.
class LogClient
  include Celluloid
  include Celluloid::Notifications

  def initialize(socket)
    @socket = socket

    subscribe(UPDATE_TOPIC, :relay)
  end

  def relay(pattern, packet)
    if pattern == UPDATE_TOPIC
      begin
        @socket << packet.to_json
      rescue Reel::SocketError
        terminate
      end
    end
  end
end
