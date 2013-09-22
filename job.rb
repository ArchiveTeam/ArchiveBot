require 'uri'
require 'uuidtools'
require 'json'

require File.expand_path('../job_analysis', __FILE__)

class Job < Struct.new(:uri, :redis)
  include JobAnalysis

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

  def set_depth(depth)
    redis.hset(ident, 'fetch_depth', depth)
  end

  def depth
    redis.hget(ident, 'fetch_depth')
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

  alias_method :completed?, :archive_url

  def bytes_downloaded
    redis.hget(ident, 'bytes_downloaded')
  end

  def warc_size
    redis.hget(ident, 'warc_size')
  end

  def error_count
    redis.hget(ident, 'error_count').to_i
  end

  def incr_error_count(by = 1)
    redis.hincrby(ident, 'error_count', by)
  end

  def aborted?
    redis.hget(ident, 'aborted')
  end

  def ttl
    redis.ttl(ident)
  end

  def formatted_ttl(ttl)
    hr = ttl / 3600
    min = (ttl % 3600) / 60
    sec = (ttl % 3600) % 60

    "#{hr}h #{min}m #{sec}s"
  end

  def to_reply
    u = archive_url

    if !u && aborted?
      ["Job aborted"].tap do |x|
        if (t = ttl)
          x << "Eligible for rearchival in #{formatted_ttl(t)}"
        end
      end
    else
      errs = error_count

      if !u
        downloaded = (bytes_downloaded.to_f / (1024 * 1024)).round(2)

        ["Fetch depth: #{depth}",
         "Downloaded #{downloaded} MiB, #{errs} errors encountered"
        ]
      else
        warc_size_mib = (warc_size.to_f / (1024 * 1024)).round(2)

        [ "Archived at #{u}, fetch depth: #{depth}, WARC size: #{warc_size_mib} MiB" ].tap do |x|
          x << "#{errs} errors encountered"

          if (t = ttl)
            x << "Eligible for rearchival in #{formatted_ttl(t)}"
          end
        end
      end
    end
  end
end
