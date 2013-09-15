require 'uri'
require 'uuidtools'

class Job < Struct.new(:uri, :redis)
  ARCHIVEBOT_V0_NAMESPACE = UUIDTools::UUID.parse('82244de1-c354-4c89-bf2b-f153ce23af43')

  def self.from_ident(ident, redis)
    url = redis.hget(ident, 'url')
    return unless url

    new(URI.parse(url), redis)
  end

  def ident
    @ident ||= UUIDTools::UUID.sha1_create(ARCHIVEBOT_V0_NAMESPACE, url).to_i.to_s(36)
  end

  def url
    uri.normalize.to_s
  end

  def queue
    redis.lpush('pending', ident)
  end

  def exists?
    !redis.keys(ident).empty?
  end

  def register
    redis.hmset(ident, 'url', url)
  end

  def archive_url
    redis.hget(ident, 'archive_url')
  end

  def to_reply
    'Nothing here yet'
  end
end
