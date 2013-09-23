require 'celluloid'
require 'celluloid/io'
require 'celluloid/redis'

class LogUpdateListener
  include Celluloid::IO
  include Celluloid::Logger

  # The Redis connection listening for log updates.
  attr_reader :lredis

  # The Redis connection used to shut down the subscription.  Can also be used
  # to run the usual Redis commands.
  attr_reader :uredis

  # The pubsub channel used for log updates.
  attr_reader :channel

  # The shutdown sentinel.  Set at initialization.
  attr_reader :shutdown_message

  def initialize(redis_url, update_channel)
    @lredis = ::Redis.new(:url => redis_url, :driver => :celluloid)
    @uredis = ::Redis.new(:url => redis_url, :driver => :celluloid)
    @channel = update_channel
    @shutdown_message = "--ArchiveBot-Shutdown-#{object_id}--".freeze

    async.start
  end

  def on_shutdown
    # implement in a subclass
  end

  def on_receive(msg)
    # implement in a subclass
  end

  def start
    lredis.subscribe(channel) do |on|
      on.message do |chan, msg|
        if msg == shutdown_message
          info "#{self.class.name} shutting down"
          lredis.unsubscribe
          on_shutdown
        else
          on_receive(msg)
        end
      end
    end
  end

  def stop
    uredis.publish(channel, shutdown_message)
  end
end
