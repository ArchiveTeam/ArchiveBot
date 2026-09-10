require 'addressable/uri'
require 'uuidtools'
require 'json'

require File.expand_path('../job_analysis', __FILE__)
require File.expand_path('../shared_config', __FILE__)

##
# Base implementations of Job methods that may be chained through modules.
module ChainableJobMethods
  def as_json
    {}
  end

  def from_hash(h)
  end
end

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
  include ChainableJobMethods
  include JobAnalysis

  ARCHIVEBOT_V0_NAMESPACE = UUIDTools::UUID.parse('82244de1-c354-4c89-bf2b-f153ce23af43')

  # When this job entered the queue.  Expressed in UTC.
  #
  # Returns a UNIX timestamp as an integer.
  attr_reader :queued_at

  # When this job was completed.  This is set by the Seesaw pipeline.
  #
  # Returns a UNIX timestamp as an integer, or nil if the job has not yet
  # finished, terminated abnormally, etc.
  attr_reader :finished_at

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

  # How many bytes have been downloaded from the target.
  #
  # Returns a Bignum, though the actual range of the returned value is
  # restricted to that of a 64-bit signed integer.  (It's a Redis limitation.)
  attr_reader :bytes_downloaded

  # How many items have been downloaded for the target.
  #
  # Returns a Bignum, though the actual range of the returned value is
  # restricted to that of a 64-bit signed integer.  (It's a Redis limitation.)
  attr_reader :items_downloaded

  # How many items have been queued for the target.
  #
  # Returns a Bignum, though the actual range of the returned value is
  # restricted to that of a 64-bit signed integer.  (It's a Redis limitation.)
  attr_reader :items_queued

  # The ID of the pipeline that this job is running on.
  attr_reader :pipeline_id

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

  # The nick of the user who initiated the job.
  #
  # Returns a string.
  attr_reader :started_by

  # When the job was started.  Set by the seesaw pipeline.
  attr_reader :started_at

  # The channel in which the job was started.
  #
  # This is assumed to be constant across the lifespan of a job.  If you move
  # ArchiveBot across channels (or networks and channels), you won't get
  # notifications for the jobs that were initiated elsewhere.
  #
  # Returns a string.
  attr_reader :started_in

  # The score of the last analyzed log entry.
  #
  # An analyzed log entry is one that has been categorized into a response set
  # bucket.
  attr_reader :last_analyzed_log_entry

  # The score of the last broadcasted log entry.
  #
  # A broadcasted log entry is one that has been sent to all connected
  # dashboard clients.
  attr_reader :last_broadcasted_log_entry

  # The score of the last trimmed log entry.
  attr_reader :last_trimmed_log_entry

  # Whether ignore pattern reports should be reported or suppressed.
  attr_reader :suppress_ignore_reports

  # Current concurrency level.
  attr_reader :concurrency

  # Minimum inter-request delay in milliseconds.
  attr_reader :delay_min

  # Maximum inter-request delay in milliseconds.
  attr_reader :delay_max

  # The rationale for this job; typically <= 32 characters.
  attr_reader :note

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
    [(100...200).freeze, 'r1xx'.freeze, %s(responses_1xx)],
    [(200...300).freeze, 'r2xx'.freeze, %s(responses_2xx)],
    [(300...400).freeze, 'r3xx'.freeze, %s(responses_3xx)],
    [(400...500).freeze, 'r4xx'.freeze, %s(responses_4xx)],
    [(500...600).freeze, 'r5xx'.freeze, %s(responses_5xx)],
    [UnknownResponseCode.new.freeze, 'runk'.freeze, :responses_unknown]
  ].freeze.each do |_, _, attr_name|
    attr_reader attr_name
  end

  def self.from_ident(ident, redis)
    url = redis.hget(ident, 'url')
    return unless url

    new(Addressable::URI.parse(url).normalize, redis).tap(&:amplify)
  end

  def self.working_job_idents(redis)
    redis.lrange('working', 0, -1)
  end

  def self.working(redis)
    idents = working_job_idents(redis)

    idents.map { |ident| from_ident(ident, redis) }
  end

  def aborted?
    !!aborted
  end

  def finished?
    !finished_at.nil?
  end

  def pending?
    started_at.nil?
  end

  def in_progress?
    !finished? && !pending?
  end

  def ident
    @ident ||= UUIDTools::UUID.sha1_create(ARCHIVEBOT_V0_NAMESPACE, uri.normalize.to_s).to_i.to_s(36)
  end

  def ignore_patterns_set_key
    "#{ident}_ignores"
  end

  def log_key
    "#{ident}_log"
  end

  def add_ignore_pattern(pattern)
    redis.sadd(ignore_patterns_set_key, pattern)
    job_parameters_changed
  end

  alias_method :add_ignore_patterns, :add_ignore_pattern

  def remove_ignore_pattern(pattern)
    redis.srem(ignore_patterns_set_key, pattern)
    job_parameters_changed
  end

  # More convenient access for modules.
  def response_buckets
    RESPONSE_BUCKETS
  end

  def amplify
    redis.hgetall(ident).tap { |h| from_hash(h) }
  end

  alias_method :reload, :amplify

  def from_hash(h)
    ts = ->(v) { v.to_i if v }

    @aborted = h['aborted']
    @abort_requested = h['abort_requested']
    @depth = h['fetch_depth']
    @bytes_downloaded = h['bytes_downloaded'].to_i
    @items_downloaded = h['items_downloaded'].to_i
    @items_queued = h['items_queued'].to_i
    @pipeline_id = h['pipeline_id']
    @warc_size = h['warc_size'].to_i
    @error_count = h['error_count'].to_i
    @queued_at = ts.(h['queued_at'])
    @finished_at = ts.(h['finished_at'])
    @started_at = ts.(h['started_at'])
    @started_by = h['started_by']
    @started_in = h['started_in']
    @last_analyzed_log_entry = h['last_analyzed_log_entry'].to_f
    @last_broadcasted_log_entry = h['last_broadcasted_log_entry'].to_f
    @last_trimmed_log_entry = h['last_trimmed_log_entry'].to_f
    @suppress_ignore_reports = h['suppress_ignore_reports']
    @concurrency = h['concurrency'].to_i
    @delay_min = h['delay_min'].to_f
    @delay_max = h['delay_max'].to_f
    @note = h['note']

    response_buckets.each do |_, bucket, attr|
      instance_variable_set("@#{attr}", h[bucket.to_s].to_i)
    end

    super
  end

  def url
    uri.to_s
  end

  def abort
    redis.hset(ident, 'abort_requested', true)
    job_parameters_changed
  end

  def fail
    redis.hset(ident, 'failed', true)
    redis.incr('jobs_failed')
    redis.lrem('pending', 0, ident)
    redis.lrem('working', 0, ident)
    redis.expire(ident, 5)
    redis.expire(log_key, 5)
    redis.expire(ignore_patterns_set_key, 5)
  end

  def queue(destination = nil, large = nil)
    queue = if destination
              "pending:#{destination}"
            elsif depth == :shallow
              'pending-ao'
            elsif large
              'pending-large'
            else
              'pending'
            end

    redis.multi do
      redis.lpush(queue, ident)
      redis.hset(ident, 'queued_at', Time.now.to_i)
    end
  end

  def register(depth, started_by, started_in, user_agent, url_file)
    @depth = depth

    slug = if url_file
             "urls-#{uri.host}-#{uri.path.split('/').last}-#{depth}"
           else
             "#{uri.host}-#{depth}"
           end

    redis.pipelined do
      redis.hmset(ident, 'url', url,
                         'fetch_depth', depth,
                         'log_key', log_key,
                         'user_agent', user_agent,
                         'ignore_patterns_set_key', ignore_patterns_set_key,
                         'slug', slug,
                         'started_by', started_by,
                         'started_in', started_in)

      if url_file
        redis.hset(ident, 'url_file', url)
      end

      silently do
        set_delay(250, 375)
        if url.start_with?("ftp://")
          set_concurrency(1)
        else
          set_concurrency(3)
        end
      end
    end

    true
  end

  def set_delay(min, max)
    redis.hmset(ident, 'delay_min', min, 'delay_max', max)
    job_parameters_changed
  end

  def set_concurrency(level)
    redis.hset(ident, 'concurrency', level)
    job_parameters_changed
  end

  def toggle_ignores(enabled)
    if enabled
      redis.hdel(ident, 'suppress_ignore_reports')
    else
      redis.hset(ident, 'suppress_ignore_reports', true)
    end

    job_parameters_changed
  end

  def add_note(note)
    redis.hset(ident, 'note', note)
  end

  def use_youtube_dl
    redis.hset(ident, 'youtube_dl', true)
  end

  def no_offsite_links!
    redis.hset(ident, 'no_offsite_links', true)
  end

  def no_cookies!
    redis.hset(ident, 'no_cookies', true)
  end

  def yahoo
    silently do
      set_delay(0, 0)
      set_concurrency(4)
    end

    job_parameters_changed
  end

  def exists?
    !redis.keys(ident).empty?
  end

  def ttl
    redis.ttl(ident)
  end

  def expire
    redis.pipelined do
      [ident, log_key, ignore_patterns_set_key].each do |k|
        redis.expire(k, 0)
      end
    end
  end

  def incr_error_count(by = 1)
    redis.hincrby(ident, 'error_count', by)
  end

  def as_json
    { 'aborted' => aborted?,
      'bytes_downloaded' => bytes_downloaded,
      'items_downloaded' => items_downloaded,
      'items_queued' => items_queued,
      'pipeline_id' => pipeline_id,
      'depth' => depth,
      'error_count' => error_count,
      'finished' => finished?,
      'ident' => ident,
      'finished_at' => finished_at,
      'queued_at' => queued_at,
      'started_at' => started_at,
      'started_by' => started_by,
      'started_in' => started_in,
      'url' => url,
      'warc_size' => warc_size,
      'suppress_ignore_reports' => suppress_ignore_reports,
      'concurrency' => concurrency,
      'delay_min' => delay_min,
      'delay_max' => delay_max,
      'note' => note
    }.tap do |h|
      response_buckets.each do |_, bucket, attr|
        h[bucket.to_s] = send(attr)
      end

      h.merge(super)
    end
  end

  def to_json
    as_json.to_json
  end

  def response_counts
    response_buckets.each_with_object({}) do |(range, bucket, attr), h|
      h[bucket] = send(attr)
    end
  end

  def total_responses
    response_counts.values.inject(0) { |c, a| c + a }
  end

  ##
  # Trims this job's logs.
  #
  # By "trim", we really mean "remove and return them".
  #
  # Note: if you run this and then run #reset_analysis, you won't get the
  # whole picture on any subsequent #analyze.  (Nor should you; after all, you
  # removed log data.)
  #
  # Theory of operation
  # -------------------
  #
  # There are two log bookmarks in a job: the last analyzed entry and the last
  # broadcasted entry.  The minimum of the two identifies the oldest useful
  # entry, i.e. the oldest entry that we still need to do something with.
  #
  # Everything older than that can be trimmed.  Here is pseudocode:
  #
  #   m = min(last_analyzed_log_entry, last_broadcasted_log_entry)
  #   l = last_trimmed_log_entry
  #
  #   if (m - l) >= THRESHOLD
  #     trim the oldest (m - l) log entries
  #     set last_trimmed_log_entry to m
  #     return trimmed entries
  #   otherwise
  #     return []
  #
  # --------------------------------------------------------------------------
  #
  # Returns the trimmed log entries interleaved with their scores, i.e.
  #
  #   [["log1", 1.0], ["log2", 2.0], ...]
  #
  # Note: As described above, the threshold parameter for this method doesn't
  # mean "number of entries to remove".  What it really determines is the
  # largest permissible gap between the last trimmed and last "useful" log
  # entry.
  #
  # Set threshold to zero to trim all stale entries.
  def trim_logs!(threshold = 1000)
    m = [last_analyzed_log_entry, last_broadcasted_log_entry].min
    l = last_trimmed_log_entry
    entries = []

    if m - last_trimmed_log_entry >= threshold
      entries = redis.zrangebyscore(log_key, l, m, :with_scores => true)
      redis.zremrangebyscore(log_key, l, m)
      redis.hset(ident, 'last_trimmed_log_entry', m)
    end

    entries
  end

  ##
  # Returns the +count+ most recent log entries for this job.
  def most_recent_log_entries(count)
    redis.zrange(log_key, -count, -1)
  end

  private

  def job_parameters_changed
    age = redis.hincrby(ident, 'settings_age', 1)

    unless @no_change_message
      redis.publish(SharedConfig.job_channel(ident), age)
    end
  end

  def silently
    begin
      @no_change_message = true
      yield
    ensure
      @no_change_message = false
    end
  end
end
