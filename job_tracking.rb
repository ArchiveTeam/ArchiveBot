require 'uuidtools'

module JobTracking
  ARCHIVEBOT_V0_NAMESPACE = UUIDTools::UUID.parse('82244de1-c354-4c89-bf2b-f153ce23af43')

  def job_ident(uri)
    uuid = UUIDTools::UUID.sha1_create(ARCHIVEBOT_V0_NAMESPACE, uri.to_s)
   
    # shorten it up a bit
    uuid.to_i.to_s(36)
  end

  def has_job?(ident, redis)
    redis.sismember('jobs', ident)
  end

  def add_job(ident, redis)
    redis.sadd('jobs', ident)
  end
end
