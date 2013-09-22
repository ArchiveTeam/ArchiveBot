# Analysis tools for job logs.
module JobAnalysis
  class UnknownResponseCode
    def include?(resp_code)
      true
    end
  end

  def log_key
    "#{ident}_log"
  end

  def response_buckets
    [
      [(100...200), '1xx'],
      [(200...300), '2xx'],
      [(300...400), '3xx'],
      [(400...500), '4xx'],
      [(500...600), '5xx'],
      [UnknownResponseCode.new, 'unknown']
    ]
  end

  def reset_analysis
    redis.multi do
      redis.hdel(ident, 'last_seen_log_index')
      
      response_buckets.each { |_, rb| redis.hdel(ident, rb) }
    end
  end

  def analyze
    start = redis.hget(ident, 'last_seen_log_index') || 0

    resps = redis.multi do
      redis.lrange(log_key, start, -1)
      redis.llen(log_key)
    end

    pending = resps[0]
    last = resps[1]

    redis.pipelined do
      pending.each do |p|
        entry = JSON.parse(p)
        wget_code = entry['wget_code']
        response_code = entry['response_code'].to_i

        if wget_code != 'RETRFINISHED'
          if response_code == 0 || response_code >= 500
            incr_error_count
          end
        end

        response_buckets.each do |rb, bucket|
          if rb.include?(response_code)
            redis.hincrby(ident, bucket, 1)
            break
          end
        end
      end

      redis.hset(ident, 'last_seen_log_index', last)
    end

    # suppress redis.pipelined return value; we don't care about it
    true
  end
end
