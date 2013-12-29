require 'celluloid'
require 'redis'

require File.expand_path('../../lib/job', __FILE__)

##
# Watches jobs for signs of heart failure, and kills the jobs once they've been
# without a heartbeat for too long.
#
# Theory of operation
# -------------------
#
# For each active job, a Reaper periodically:
#
# 1. Checks for a "last acknowledged heartbeat" field in the job's metadata.
#    If one does not exist but a heartbeat field exists, it copies the
#    heartbeat data to the last acknowledged heartbeat (hereafter LAH) field.
#
# 2. If an LAH value exists, compares it to the current heartbeat value.
#
# 3. The job is considered alive if current heartbeat value > LAH value.
#    Otherwise, it is considered in limbo.
#
# 4. If the job is alive, copies the current heartbeat value to the LAH field.
#    If a death timer is active, the timer is reset.
#
# 5. If the job is in limbo, begins a death timer or increments an existing
#    timer if one already exists.  If the death timer exceeds a given
#    threshold, the job is reaped.
#
# The death threshold is 3600 cycles without any heartbeat activity.  One cycle
# is triggered every two seconds.
class Reaper
  include Celluloid

  def initialize(redis)
    @redis = ::Redis.new(:url => redis)
    @check = every(2) { check }
  end

  private

  def check
    Job.working_job_idents(@redis).each { |ident| check_one(ident) }
  end

  HB = 'heartbeat'
  LAH = 'last_acknowledged_heartbeat'
  DEATH_TIMER = 'death_timer'
  THRESHOLD = 3600

  def check_one(ident)
    data = @redis.hmget(ident, LAH, HB)
    old = data[0]
    new = data[1]

    # We can't reap the undead: if there's no heartbeat for the job, just skip
    # it.
    return if new.nil?

    # If no heartbeat has yet been acknowledged, acknowledge the current
    # heartbeat and return.
    if old.nil?
      @redis.hset(ident, LAH, new)
      return
    end

    # Otherwise, do the comparison.
    if new.to_i <= old.to_i
      # Start or increment the death timer.
      count = @redis.hincrby(ident, DEATH_TIMER, 1)

      if count >= THRESHOLD
        # TODO: It's dead, Jim
        puts "Job #{ident} has failed #{count} checks and needs to be reaped"
      end
    else
      @redis.hmset(ident, LAH, new, DEATH_TIMER, 0)
    end
  end
end
