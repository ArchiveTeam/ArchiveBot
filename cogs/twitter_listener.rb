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
# which is managed in ArchiveBot's CouchDB instance.  If the whitelist says
# that the source checks out, a TwitterRequest is queued up in ArchiveBot's
# Redis instance, where it is handled by the TwitterConcierge.
class TwitterListener
  include Celluloid
  include Celluloid::Logger

  attr_reader :config
  attr_reader :db
  attr_reader :helper

  def initialize(concierge_name, db_uri, db_credentials, twitter_config_filename)
    @config = JSON.parse(File.read(twitter_config_filename))
    @db = Couchdb.new(db_uri, db_credentials)
    @helper = Helper.new(concierge_name)

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

    attr_reader :concierge_name

    def initialize(concierge_name)
      @concierge_name = concierge_name
    end

    def process_tweet(tweet)
      urls = expand_urls(tweet.text)

      urls.each do |u|
        req = TwitterRequest.new(u, tweet.id, tweet.user.id, tweet.user.screen_name)

        Celluloid::Actor[concierge_name].handle(req)
      end

      info "Passed #{urls.join(', ')} to concierge (from #{tweet.user.screen_name})"
    end
  end
end
