require 'uuidtools'

module JobTracking
  ARCHIVEBOT_V0_NAMESPACE = UUIDTools::UUID.parse('82244de1-c354-4c89-bf2b-f153ce23af43')

  def job_ident(uri)
    uuid = UUIDTools::UUID.sha1_create(ARCHIVEBOT_V0_NAMESPACE, uri.to_s)
   
    # shorten it up a bit
    uuid.to_i.to_s(36)
  end

  def has_job?(ident)
    redis { |r| r.sismember('jobs', ident) }
  end

  def add_job(ident)
    redis { |r| r.sadd('jobs', ident) }
  end

  def start_job(ident, uri, at = Time.now)
    redis do |r|
      r.hmset(ident, 'status', 'started', 'uri', uri, 'updated_at', at)
    end
  end

  def fail_job(ident, why, at = Time.now)
    redis do |r|
      r.multi do
        r.hmset(ident, 'status', 'failed', 'reason', why, 'updated_at', at)
        r.srem('jobs', ident)
      end
    end
  end
end
