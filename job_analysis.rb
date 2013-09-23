# Analysis tools for job logs.
module JobAnalysis
  def log_key
    "#{ident}_log"
  end

  def reset_analysis
    redis.multi do
      redis.hdel(ident, 'last_seen_log_index')
      response_buckets.each { |_, bucket, _| redis.hdel(ident, bucket) }
    end
  end

  def analyze
    start = last_seen_log_index

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

        response_buckets.each do |range, bucket, _|
          if range.include?(response_code)
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
