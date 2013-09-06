require 'sidekiq'
require 'uri'

require File.expand_path('../archive', __FILE__)
require File.expand_path('../job_tracking', __FILE__)

class Brain
  include JobTracking

  attr_reader :schemes

  def initialize(schemes)
    @schemes = schemes
  end

  def redis(&block)
    Sidekiq.redis(&block)
  end

  def request_archive(m, param)
    # Do we have a valid URI?
    begin
      uri = URI.parse(param).normalize
    rescue URI::InvalidURIError => e
      reply m, "Sorry, that doesn't look like a URL to me."
      return
    end

    # Is the URI in our list of recognized schemes?
    if !schemes.include?(uri.scheme)
      reply m, "Sorry, I can only handle #{schemes.join(', ')}."
      return
    end

    # Is the job already known?
    ident = job_ident(uri)
    if has_job?(ident)
      reply m, "That URL is already being processed.  Use !status #{ident} for updates."
      return
    end

    # OK, add the job and queue it up.
    add_job(ident)
    Archive.perform_async(uri, ident)
    reply m, "Archiving #{uri.to_s}; use !status #{ident} for updates."
  end

  private

  def reply(m, *args)
    m.reply "#{m.user.nick}: #{args.join(' ')}"
  end
end
