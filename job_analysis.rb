# Analysis tools for job logs.
module JobAnalysis
  def log_key
    "#{ident}_log"
  end

  def checkpoint_key
    'last_analyzed_log_entry'
  end

  def broadcast_checkpoint_key
    'last_broadcasted_log_entry'
  end

  def reset_analysis
    redis.multi do
      redis.hdel(ident, checkpoint_key)
      redis.hdel(ident, broadcast_checkpoint_key)
      response_buckets.each { |_, bucket, _| redis.hdel(ident, bucket) }
    end
  end

  def new_entries(start)
    redis.zrangebyscore(log_key, "(#{start}", '+inf', :with_scores => true)
  end

  def read_new_entries
    start = redis.hget(ident, broadcast_checkpoint_key).to_f
    entries = new_entries(start)

    return [] if entries.empty?

    redis.hset(ident, broadcast_checkpoint_key, entries.last.last)
    entries.map { |entry, _| JSON.parse(entry) }
  end

  def analyze
    start = redis.hget(ident, checkpoint_key).to_f
    resps = new_entries(start)

    return if resps.empty?

    last = resps.last.last

    redis.pipelined do
      resps.each do |p, _|
        entry = JSON.parse(p)

        next unless entry['type'] == 'download'

        wget_code = entry['wget_code']
        response_code = entry['response_code'].to_i

        if entry['is_error']
          incr_error_count
        end

        response_buckets.each do |range, bucket, _|
          if range.include?(response_code)
            redis.hincrby(ident, bucket, 1)
            break
          end
        end
      end

      redis.hset(ident, checkpoint_key, last)
    end

    # suppress redis.pipelined return value; we don't care about it
    true
  end
end
