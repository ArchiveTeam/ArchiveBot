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

  def abort
    redis.hset(ident, 'aborted', true)
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

  def update_warc_size
    warc_path = redis.hget(ident, 'source_warc_file')

    if warc_path
      begin
        redis.hset(ident, 'last_warc_size', File.stat(warc_path).size)
      rescue
        # ignore it
      end
    end
  end

  def last_warc_size
    redis.hget(ident, 'last_warc_size')
  end

  def last_log_entry
    redis.lindex("#{ident}_log", -1) || '(none)'
  end

  def aborted?
    redis.hget(ident, 'aborted')
  end

  def expiring?
    redis.ttl(ident) != -1
  end

  def formatted_ttl
    t = redis.ttl(ident)

    hr = t / 3600
    min = (t % 3600) / 60
    sec = (t % 3600) % 60

    "#{hr}h #{min}m #{sec}s"
  end

  def to_reply
    u = archive_url
    warc_size = (last_warc_size.to_f / (1024 * 1024)).round(2)

    if aborted?
      ["Job aborted"].tap do |x|
        if expiring?
          x << "Eligible for rearchival in #{formatted_ttl}"
        end
      end
    else
      if !u
        ["Last log entry: #{last_log_entry}",
         "WARC size: #{warc_size} MiB"
        ]
      else
        [ "Archived at #{u}, #{warc_size} MiB" ].tap do |x|
          if expiring?
            x << "Eligible for rearchival in #{formatted_ttl}"
          end
        end
      end
    end
  end
end
