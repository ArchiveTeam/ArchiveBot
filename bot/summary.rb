class Summary
  attr_reader :redis
  attr_reader :pending, :working, :completed, :aborted, :failed

  def initialize(redis)
    @redis = redis
  end

  def run
    @pending = redis.llen('pending')
    @working = redis.llen('working')
    @completed = redis.get('jobs_completed') || 0
    @aborted = redis.get('jobs_aborted') || 0
    @failed = redis.get('jobs_failed') || 0
  end

  def to_s
    "Job status: #{completed} completed, #{aborted} aborted, #{failed} failed, #{working} in progress, #{pending} pending"
  end
end
