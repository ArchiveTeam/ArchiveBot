require 'uri'

require File.expand_path('../../lib/job', __FILE__)
require File.expand_path('../summary', __FILE__)
require File.expand_path('../post_registration_hook', __FILE__)
require File.expand_path('../add_ignore_sets', __FILE__)
require File.expand_path('../job_status_generation', __FILE__)
require File.expand_path('../parameter_parsing', __FILE__)

Job.send(:include, JobStatusGeneration)

class Brain
  include ParameterParsing
  include PostRegistrationHook
  include AddIgnoreSets

  attr_reader :couchdb
  attr_reader :redis
  attr_reader :schemes
  attr_reader :url_pattern

  def initialize(schemes, redis, couchdb)
    @couchdb = couchdb
    @redis = redis
    @schemes = schemes
    @url_pattern ||= %r{(?:#{schemes.join('|')})://.+}
  end

  def find_job(ident, m)
    job = Job.from_ident(ident, redis)

    if !job
      reply m, "Sorry, I don't know anything about #{ident}."
    else
      yield job
    end
  end

  def request_archive(m, target, params, depth='inf')
    # Is the user authorized?
    return unless authorized?(m)

    # Do we have a valid URI?
    begin
      uri = URI.parse(target)
    rescue URI::InvalidURIError => e
      reply m, "Sorry, that doesn't look like a URL to me."
      return
    end

    # Parse parameters.
    h = parse_params(params)

    # Eliminate unknown parameters.  If we find any such parameters, report
    # them and don't run the job.
    unknown = delete_unknown_parameters(h, :archive)
    if !unknown.empty?
      reply m, "Sorry, #{unknown.join(', ')} are unrecognized parameters."
      return
    end

    # Is the URI in our list of recognized schemes?
    if !schemes.include?(uri.scheme)
      reply m, "Sorry, I can only handle #{schemes.join(', ')}."
      return
    end

    job = Job.new(uri, redis)

    # Is the job already known?
    if job.exists?
      reply m, "Job for #{uri} already exists."

      # OK, print out its status.
      job.amplify
      status = job.to_status
      reply m, *status
      return
    end

    # OK, add the job.
    batch_reply(m) do
      job.register(depth, m.user.nick, m.channel.name)

      if depth == :shallow
        reply m, "Queued #{uri.to_s} for archival without recursion."
      else
        reply m, "Queued #{uri.to_s}."
      end

      destination = nil

      if h['pipeline']
        destination = h['pipeline'].first
        reply m, "Job will run on pipeline #{destination}."
      end

      reply m, "Use !status #{job.ident} for updates, !abort #{job.ident} to abort."

      run_post_registration_hooks(m, job, h)

      if depth == :shallow
        # If this is a shallow depth job, it gets priority over jobs that go
        # deeper.
        job.queue(destination, :front)
      else
        # If this job goes deeper, shove it at the back of the queue.
        job.queue(destination)
      end
    end
  end

  def request_status_by_url(m, url)
    job = Job.new(URI(url), redis)

    if !job.exists?
      rep = []

      # Was there a successful attempt in the past?
      doc = couchdb.latest_job_record(url)

      if doc
        queued_time = if doc['queued_at']
                        Time.at(doc['queued_at']).to_s
                      else
                        '(unknown)'
                      end

        rep << "#{url}:"

        if doc['finished']
          rep << "Job finished; last ran at #{queued_time}."
          rep << "Eligible for re-archiving."
        elsif doc['aborted']
          rep << "Job aborted; last ran at #{queued_time}."
          rep << "Eligible for re-archiving."
        else
          rep << "Hmm...I've seen #{url} before, but I can't figure out its status :("
        end
      else
        rep << "#{url} has not been archived."

        # Were there any attempts on child URLs?
        child_attempts = couchdb.attempts_on_children(url)

        if child_attempts > 0
          if child_attempts == 1
            rep << "However, there has been #{child_attempts} download attempt on child URLs."
          else
            rep << "However, there have been #{child_attempts} download attempts on child URLs."
          end

          rep << "See the ArchiveBot dashboard for more information."
        end
      end

      reply m, *rep
    else
      job.amplify
      reply m, *job.to_status
    end
  end

  def request_status(m, job)
    reply m, *job.to_status
  end

  def initiate_abort(m, job)
    return unless authorized?(m)

    job.abort
    reply m, "Initiated abort for #{job.url}."
  end

  def add_ignore_pattern(m, job, pattern)
    return unless authorized?(m)

    job.add_ignore_pattern(pattern)
    reply m, "Added ignore pattern #{pattern} to job #{job.ident}."
  end

  def add_ignore_sets(m, job, names)
    return unless authorized?(m)

    if !names.respond_to?(:each)
      names = names.split(',').map(&:strip)
    end

    return unless names && !names.empty?

    ignore_pairs = couchdb.resolve_ignore_sets(names)

    resolved = ignore_pairs.map(&:first).uniq
    patterns = ignore_pairs.map(&:last)

    job.add_ignore_patterns(patterns) unless patterns.empty?

    reply m, "Added #{patterns.length} ignore patterns to job #{job.ident}."

    unknown = names - resolved

    if !unknown.empty?
      reply m, "The following sets are unknown: #{unknown.join(', ')}"
    end
  end

  def expire(m, job)
    return unless authorized?(m)

    if job.ttl < 0
      reply m, "Job #{job.ident} does not yet have an expiry timer."
    else
      job.expire
      reply m, "Job #{job.ident} expired."
    end
  end

  def remove_ignore_pattern(m, job, pattern)
    return unless authorized?(m)

    job.remove_ignore_pattern(pattern)
    reply m, "Removed ignore pattern #{pattern} from job #{job.ident}."
  end

  def set_delay(job, min, max, m)
    return unless authorized?(m)
    return unless delay_ok?(min, max, m)

    job.set_delay(min, max)

    reply m, "Inter-request delay for job #{job.ident} set to [#{min}, #{max}] ms."
  end

  def set_pagereq_delay(job, min, max, m)
    return unless authorized?(m)
    return unless delay_ok?(min, max, m)

    job.set_pagereq_delay(min, max)

    reply m, "Page requisite delay for job #{job.ident} set to [#{min}, #{max}] ms."
  end

  def request_summary(m)
    s = Summary.new(redis)
    s.run

    reply m, s
  end

  private

  VALID_PARAMETERS = {
    :archive => %w(ignore_sets pipeline)
  }

  def delete_unknown_parameters(h, command)
    [].tap do |a|
      h.keys.each do |k|
        if !VALID_PARAMETERS[command].include?(k)
          h.delete k
          a << k
        end
      end
    end
  end

  def authorized?(m)
    if !m.channel.opped?(m.user)
      reply m, "Sorry, only channel operators may use that command."
      return false
    end

    return true
  end

  def delay_ok?(min, max, m)
    if min.to_f > max.to_f
      reply m, 'Sorry, min delay must be less than or equal to max delay.'
      return false
    end

    true
  end

  def batch_reply(m)
    c = Thread.current

    begin
      c[:batch_mode] = true
      c[:buf] = []
      yield
      c[:batch_mode] = false
      reply m, *c[:buf]
    ensure
      # If we catch an exception, reset the batch mode flag, but don't send
      # anything.
      c[:buf] = false
    end
  end

  def reply(m, *args)
    if Thread.current[:batch_mode]
      Thread.current[:buf] += args
    else
      args.each { |msg| m.safe_reply(msg, true) }
    end
  end
end
