require 'json'

##
# Represents an archive request from Twitter.
class TwitterRequest < Struct.new(:url, :tweet_id, :user_id, :username)
  ##
  # The Redis key where accepted requests live.
  ACCEPTED_REQUESTS_KEY = 'twitter_listener:accepted_requests'

  def self.from_json(json)
    new(json['url'],
        json['tweet_id'],
        json['user_id'],
        json['username'])
  end

  ##
  # Queue requests in Redis.
  def self.queue(requests, redis)
    redis.sadd(ACCEPTED_REQUESTS_KEY, requests.map(&:to_json))
  end

  def to_json(*)
    { url: url,
      tweet_id: tweet_id,
      user_id: user_id,
      username: username
    }.to_json
  end
end
