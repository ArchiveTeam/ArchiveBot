require 'celluloid'
require 'celluloid/io'
require 'celluloid/redis'

require File.expand_path('../job', __FILE__)

class LogAnalyzer
  include Celluloid::IO
  include Celluloid::Logger

  # The Redis connection listening for log updates.
  attr_reader :lredis
 
  # The Redis connection used to update job status.
  attr_reader :uredis

  # The pubsub channel used for log updates.
  attr_reader :channel

  # The shutdown sentinel.
  SHUTDOWN_MESSAGE = '--ArchiveBot-Shutdown--'

  def initialize(redis_url, update_channel)
    @lredis = ::Redis.new(:url => redis_url, :driver => :celluloid)
    @uredis = ::Redis.new(:url => redis_url, :driver => :celluloid)
    @jobs = {}
    @channel = update_channel

    async.start
  end

  def start
    lredis.subscribe(channel) do |on|
      on.message do |chan, ident|
        if ident == SHUTDOWN_MESSAGE
          debug 'Shutting down LogAnalyzer'
          lredis.unsubscribe
          @jobs.clear
        else
          if !@jobs.has_key?(ident)
            @jobs[ident] = ::Job.from_ident(ident, uredis)
          end

          job = @jobs[ident]
          job.analyze

          @jobs.delete(ident) if can_forget?(job)
        end
      end
    end
  end

  def stop
    uredis.publish(channel, SHUTDOWN_MESSAGE)
  end

  private

  def can_forget?(job)
    resps = uredis.pipelined do
      job.completed?
      job.aborted?
    end

    resps.any?
  end
end
