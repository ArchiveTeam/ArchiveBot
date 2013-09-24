require 'uri'
require 'uuidtools'
require 'json'

require File.expand_path('../job_analysis', __FILE__)

# Ruby representation of an archive job.
#
# This class has a lot of query methods and a few mutators.  The mutators DO
# NOT update the cached data in the instance.  If you need to mutate and then
# read out the changed data from an instance, you MUST call #reload before
# reading, e.g.
#
#     j.incr_error_count
#     j.error_count       # returns stale data
#
#     j.incr_error_count
#     j.reload            # ok, now we're up to date
#     j.error_count
#
# As you may have guessed, none of ArchiveBot's facilities really use the
# second pattern.
class Job < Struct.new(:uri, :redis)
  include JobAnalysis

  ARCHIVEBOT_V0_NAMESPACE = UUIDTools::UUID.parse('82244de1-c354-4c89-bf2b-f153ce23af43')

  # Whether this job was aborted.
  #
  # Returns a boolean.
  attr_reader :aborted

  # Whether an abort was requested.
  #
  # Returns a boolean.
  attr_reader :abort_requested

  # The fetch depth for this job.
  #
  # Returns a string.  Typical return values are "inf" (infinite depth) and
  # "shallow" (no recursion).
  attr_reader :depth

  # A URL for the fetched WARC, if one has been generated.
  #
  # Returns a URL as a string or nil.
  attr_reader :archive_url

  # How many bytes have been downloaded from the target.
  #
  # Returns a Bignum, though the actual range of the returned value is
  # restricted to that of a 64-bit signed integer.  (It's a Redis limitation.)
  attr_reader :bytes_downloaded

  # The size of the generated WARC.
  #
  # This is nil until the job completes.
  #
  # Returns a Numeric.  The range of the returned value is dependent on wget's
  # file size limitations.
  attr_reader :warc_size

  # The number of errors encountered by this job.
  #
  # An "error" is pretty loosely defined.  See JobAnalysis#analyze for more
  # details.
  #
  # Returns an integer.
  attr_reader :error_count

  # A bucket for HTTP responses that aren't in the (100..599) range.
  class UnknownResponseCode
    def include?(resp_code)
      true
    end
  end

  # Response counts by response code.
  #
  # Generally, it is easier to use #response_counts, but you can get the same
  # data this way.
  #
  # Bucket names are frozen strings and not symbols because redis-rb returns
  # hash keys as strings, and throwing #to_s everywhere is totally not
  # necessary.
  RESPONSE_BUCKETS = [
    [(100...200).freeze, '1xx'.freeze, %s(responses_1xx)],
    [(200...300).freeze, '2xx'.freeze, %s(responses_2xx)],
    [(300...400).freeze, '3xx'.freeze, %s(responses_3xx)],
    [(400...500).freeze, '4xx'.freeze, %s(responses_4xx)],
    [(500...600).freeze, '5xx'.freeze, %s(responses_5xx)],
    [UnknownResponseCode.new.freeze, 'unknown'.freeze, :responses_unknown]
  ].freeze.each do |_, _, attr_name|
    attr_reader attr_name
  end

  def self.from_ident(ident, redis)
    url = redis.hget(ident, 'url')
    return unless url

    new(URI.parse(url), redis).tap(&:amplify)
  end

  def aborted?
    !!aborted
  end

  def completed?
    !!archive_url
  end

  def ident
    @ident ||= UUIDTools::UUID.sha1_create(ARCHIVEBOT_V0_NAMESPACE, url).to_i.to_s(36)
  end

  # More convenient access for modules.
  def response_buckets
    RESPONSE_BUCKETS
  end

  def amplify
    redis.hgetall(ident).tap do |h|
      @aborted = h['aborted']
      @abort_requested = h['abort_requested']
      @depth = h['fetch_depth']
      @archive_url = h['archive_url']
      @bytes_downloaded = h['bytes_downloaded'].to_i
      @warc_size = h['warc_size'].to_i
      @error_count = h['error_count'].to_i

      response_buckets.each do |_, bucket, attr|
        instance_variable_set("@#{attr}", h[bucket.to_s].to_i)
      end
    end
  end

  alias_method :reload, :amplify

  def url
    uri.normalize.to_s
  end

  def abort
    redis.hset(ident, 'abort_requested', true)
  end

  def queue
    redis.lpush('pending', ident)
  end

  def register
    redis.hmset(ident, 'url', url)
  end

  def exists?
    !redis.keys(ident).empty?
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

  def set_depth(depth)
    redis.hset(ident, 'fetch_depth', depth)
  end

  def incr_error_count(by = 1)
    redis.hincrby(ident, 'error_count', by)
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

  def response_counts
    response_buckets.each_with_object({}) do |(range, bucket, attr), h|
      h[bucket] = send(attr)
    end
  end

  def total_responses
    response_counts.values.inject(0) { |c, a| c + a }
  end
end
