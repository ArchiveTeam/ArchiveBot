class Summary
  attr_reader :redis
  attr_reader :pending, :pendingao, :pendingothers, :working, :completed, :aborted, :failed

  def initialize(redis)
    @redis = redis
  end

  def run
    @pending = redis.llen('pending')
    @pendingao = redis.llen('pending-ao')
    @pendingothers = get_pending_others
    @working = redis.llen('working')
    @completed = redis.get('jobs_completed') || 0
    @aborted = redis.get('jobs_aborted') || 0
    @failed = redis.get('jobs_failed') || 0
  end

  def get_pending_others
    pendingothers = 0
    redis.scan_each(:match => "pending:*") { |key| pendingothers += redis.llen(key) }
    pendingothers
  end

  def to_s
    "Job status: #{completed} completed, #{aborted} aborted, #{failed} failed, #{working} in progress, #{pending} pending, #{pendingao} pending-ao, #{pendingothers} pending in other queues"
  end
end
