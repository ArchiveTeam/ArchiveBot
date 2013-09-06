require 'sidekiq'
require 'uuidtools'

class Job < Struct.new(:uri)
  ARCHIVEBOT_V0_NAMESPACE = UUIDTools::UUID.parse('82244de1-c354-4c89-bf2b-f153ce23af43')

  def ident
    @ident ||= UUIDTools::UUID.sha1_create(ARCHIVEBOT_V0_NAMESPACE, url).to_i.to_s(36)
  end

  def exists?
    redis { |c| !c.keys(ident).empty? }
  end

  def register
    redis { |c| c.hmset(ident, 'status', 'pending', 'url', url) }
  end

  def archive_url
    redis { |c| c.hget(ident, 'archive_url') }
  end

  private

  def url
    uri.normalize.to_s
  end

  def redis(&block)
    Sidekiq.redis(&block)
  end
end
