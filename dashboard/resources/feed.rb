require 'digest/sha1'
require 'time'
require 'webmachine'
require 'erubis'

class Feed < Webmachine::Resource
  REDIS_KEY_DONE = 'tweets:done'
  RSS_FILENAME = File.expand_path('../../assets/templates/rss_feed.erubis', __FILE__)
  ATOM_FILENAME = File.expand_path('../../assets/templates/atom_feed.erubis', __FILE__)
  class << self
    attr_accessor :redis
  end

  def content_types_provided
    [
      ['application/atom+xml', :to_atom],
      ['application/rss+xml', :to_rss],
      ['application/json', :to_json],
    ]
  end

  def to_rss
    input = File.read(RSS_FILENAME)
    eruby = Erubis::Eruby.new(input)
    messages = prepped_messages(true)
    eruby.result(:items=>messages)
  end

  def to_atom
    input = File.read(ATOM_FILENAME)
    eruby = Erubis::Eruby.new(input)
    messages = prepped_messages(false)
    eruby.result(:items=>messages, :updated => Time.now.iso8601)
  end

  def to_json
    prepped_messages(false).to_json
  end

  protected

  def prepped_messages(rfc822_date)
    messages = Feed::redis.zrange(REDIS_KEY_DONE, -100, -1, {withscores: true})

    prepped_messages = []

    for message, timestamp in messages.reverse_each
      id = Digest::SHA1.hexdigest("#{timestamp}-#{message}")
      time = Time.at(timestamp)

      if rfc822_date
        date_str = time.rfc2822
      else
        date_str = time.iso8601
      end

      prepped_messages.push([date_str, message, id])
    end

    return prepped_messages
  end
end

class AtomFeed <Feed
  def content_types_provided
      [
        ['application/atom+xml', :to_atom],
      ]
    end
end

class RssFeed < Feed
  def content_types_provided
      [
        ['application/rss+xml', :to_rss],
      ]
    end
end
