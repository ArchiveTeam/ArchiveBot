require 'uri'

require File.expand_path('../job', __FILE__)
require File.expand_path('../summary', __FILE__)

class Brain
  attr_reader :schemes
  attr_reader :redis

  def initialize(schemes, redis)
    @schemes = schemes
    @redis = redis
  end

  def request_archive(m, param)
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
      # Does its archive have a URL?
      if (archive_url = job.archive_url)
        rep = "That URL was previously archived to #{archive_url}."

        # Is the archive record expiring?  If so, tell the requestor when they
        # may resubmit the archive request.
        if job.expiring?
          rep << "  You may resubmit it in #{job.formatted_ttl}."
        end

        reply m, rep
      else
        reply m, "That URL is already being processed.  Use !status #{job.ident} for updates."
      end

      return
    end

    # OK, add the job and queue it up.
    job.register
    job.queue
    reply m, "Archiving #{uri.to_s}."
    reply m, "Use !status #{job.ident} for updates, !abort #{job.ident} to abort."
  end

  def request_status(m, ident)
    job = Job.from_ident(ident, redis)

    if !job
      reply m, "Sorry, I don't know anything about job #{ident}."
      return
    end

    job.update_warc_size
    reply m, "Job update for #{job.uri}"

    job.to_reply.each { |r| reply m, r }
    return
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
    m.reply "#{m.user.nick}: #{args.join(' ')}"
  end
end
