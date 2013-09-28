require 'uri'

require File.expand_path('../job', __FILE__)
require File.expand_path('../summary', __FILE__)

class Brain
  attr_reader :history_db
  attr_reader :redis
  attr_reader :schemes
  attr_reader :url_pattern

  def initialize(schemes, redis, history_db)
    @history_db = history_db
    @redis = redis
    @schemes = schemes
    @url_pattern ||= %r{(?:#{schemes.join('|')})://.+}
  end

  def request_archive(m, param, depth='inf')
    # Is the user authorized?
    return unless authorized?(m)

    # Do we have a valid URI?
    begin
      uri = URI.parse(param)
    rescue URI::InvalidURIError => e
      reply m, "Sorry, that doesn't look like a URL to me."
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
      status = job.to_status
      reply m, *status
      return
    end

    # OK, add the job and queue it up.
    job.register
    job.set_depth(depth)
    job.queue

    if depth == :shallow
      reply m, "Archiving #{uri.to_s} without recursion."
    else
      reply m, "Archiving #{uri.to_s}."
    end

    reply m, "Use !status #{job.ident} for updates, !abort #{job.ident} to abort."
  end

  def request_status_by_url(m, url)
    job = Job.new(URI(url), redis)

    if !job.exists?
      rep = []

      # Was there a successful attempt in the past?
      doc = history_db.latest_job_record(url)

      if doc
        queued_time = Time.at(doc['queued_at']).to_s
        rep << "#{url}:"

        if doc['completed']
          rep << "Archived to #{doc['archive_url']}; last ran at #{queued_time}."
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
        child_attempts = history_db.attempts_on_children(url)

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

  def request_summary(m)
    s = Summary.new(redis)
    s.run

    reply m, s
  end

  private

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
