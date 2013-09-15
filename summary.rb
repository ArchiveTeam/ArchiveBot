class Summary
  attr_reader :redis
  attr_reader :pending, :working, :completed

  def initialize(redis)
    @redis = redis
  end

  def run
    @pending = redis.llen('pending')
    @working = redis.llen('working')
    @completed = redis.get('jobs_completed')
  end

  def to_s
    "Job status: #{completed} completed, #{working} in progress, #{pending} pending"
  end
end
