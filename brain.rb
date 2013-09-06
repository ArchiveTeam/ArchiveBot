require 'sidekiq'
require 'uri'

require File.expand_path('../job', __FILE__)

class Brain
  attr_reader :schemes

  def initialize(schemes)
    @schemes = schemes
  end

  def request_archive(m, param)
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

    job = Job.new(uri)

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

    reply m, "Archiving #{uri.to_s}; use !status #{job.ident} for updates."
  end

  private

  def reply(m, *args)
    m.reply "#{m.user.nick}: #{args.join(' ')}"
  end
end
