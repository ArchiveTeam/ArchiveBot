require 'celluloid'
require 'json'
require 'redis'
require 'twitter'

require File.expand_path('../../lib/couchdb', __FILE__)
require File.expand_path('../../lib/twitter_request', __FILE__)
require File.expand_path('../tweet_url_extraction', __FILE__)

##
# Listens for Twitter messages of the form
#
#   @USERNAME would you kindly [...]
#
# and extracts URLs from the [...] bit.
#
# This listener compares the source username against an internal whitelist,
# which is managed in ArchiveBot's CouchDB instance.
class TwitterListener
  include Celluloid
  include Celluloid::Logger

  attr_reader :config
  attr_reader :db
  attr_reader :helper

  def initialize(redis_url, db_uri, db_credentials, twitter_config_filename)
    @config = JSON.parse(File.read(twitter_config_filename))
    @db = Couchdb.new(db_uri, db_credentials)
    @helper = Helper.new(redis_url)

    link(helper)

    async.start
  end

  def start
    username = config.delete('username')
    trigger = "#{username} would you kindly"

    client = Twitter::Streaming::Client.new(config)

    client.filter(track: trigger) do |object|
      if object.is_a?(Twitter::Tweet)
        # Screen names change.  User IDs are (closer to) forever.
        user_id = object.user.id
        screen_name = object.user.screen_name

        if db.accept_tweets_from(user_id)
          info "Processing tweet from #{user_id} (#{screen_name})"

          # Twitter::Streaming::Client#filter can't be suspended by Celluloid's
          # task-switching code, so we shove the tweet-processing work to a
          # helper actor.
          helper.async.process_tweet(object)
        else
          info "Rejected tweet from #{user_id} (#{screen_name})"
        end
      end
    end
  end

  class Helper
    include Celluloid
    include Celluloid::Logger
    include TweetUrlExtraction

    attr_reader :redis

    def initialize(redis_url)
      @redis = ::Redis.new(:url => redis_url)
    end

    def process_tweet(tweet)
      urls = expand_urls(tweet.text)

      requests = urls.map do |u|
        TwitterRequest.new(u, tweet.id, tweet.user.id, tweet.user.screen_name)
      end

      TwitterRequest.queue(requests, redis)

      info "Added #{urls.join(', ')} to requests queue (from #{tweet.user.screen_name})"
    end
  end
end
