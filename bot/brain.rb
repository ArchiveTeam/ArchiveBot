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
    rep = []
    job.register(depth, m.user.nick, m.channel.name)

    if depth == :shallow
      rep << "Archiving #{uri.to_s} without recursion."
    else
      rep << "Archiving #{uri.to_s}."
    end

    rep <<  "Use !status #{job.ident} for updates, !abort #{job.ident} to abort."

    run_post_registration_hooks(job, h, rep)

    # Queue it up.
    job.queue

    reply m, *rep
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
          if doc['archive_url']
            rep << "Archived to #{doc['archive_url']}; last ran at #{queued_time}."
          else
            rep << "Job finished; last ran at #{queued_time}."
          end

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

  def request_status_by_ident(m, ident)
    job = Job.from_ident(ident, redis)

    if !job
      reply m, "Sorry, I don't know anything about job #{ident}."
    else
      reply m, *job.to_status
    end
  end

  def initiate_abort(m, ident)
    # Is the user authorized?
    return unless authorized?(m)

    job = Job.from_ident(ident, redis)

    if !job
      reply m, "Sorry, I don't know anything about job #{ident}."
      return
    end

    job.abort
    reply m, "Initiated abort for #{job.url}."
  end

  def add_ignore_pattern(m, ident, pattern)
    # Is the user authorized?
    return unless authorized?(m)

    job = Job.from_ident(ident, redis)

    if !job
      reply m, "Sorry, I don't know anything about job #{ident}."
      return
    end

    job.add_ignore_pattern(pattern)
    reply m, "Added ignore pattern #{pattern} to job #{ident}."
  end

  def remove_ignore_pattern(m, ident, pattern)
    # Is the user authorized?
    return unless authorized?(m)

    job = Job.from_ident(ident, redis)

    if !job
      reply m, "Sorry, I don't know anything about job #{ident}."
      return
    end

    job.remove_ignore_pattern(pattern)
    reply m, "Removed ignore pattern #{pattern} from job #{ident}."
  end

  def request_summary(m)
    s = Summary.new(redis)
    s.run

    reply m, s
  end

  private

  VALID_PARAMETERS = {
    :archive => %w(ignore_sets)
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
      reply m, "Sorry, only channel operators may start archive jobs."
      return false
    end

    return true
  end

  def reply(m, *args)
    args.each { |msg| m.reply "#{m.user.nick}: #{msg}" }
  end
end
