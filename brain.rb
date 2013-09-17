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
    # Is the user an op?
    if m.channel.opped?(m.user)
      reply m, "Sorry, only channel operators may start archive jobs."
      return
    end

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
        reply m, "That URL was previously archived to #{archive_url}.  Re-archiving is not yet supported."
      else
        reply m, "That URL is already being processed.  Use !status #{job.ident} for updates."
      end

      return
    end

    # OK, add the job and queue it up.
    job.register
    job.queue
    reply m, "Archiving #{uri.to_s}; use !status #{job.ident} for updates."
  end

  def request_status(m, ident)
    job = Job.from_ident(ident, redis)

    if !job
      reply m, "Sorry, I don't know anything about job #{ident}."
      return
    end

    reply m, "Job update for #{job.uri}"
    reply m, job.to_reply
    return
  end

  def request_summary(m)
    s = Summary.new(redis)
    s.run

    reply m, s
  end

  private

  def reply(m, *args)
    m.reply "#{m.user.nick}: #{args.join(' ')}"
  end
end
