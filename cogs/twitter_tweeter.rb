require 'twitter'
require 'json'

# Updates a Twitter timeline. It uses Redis as the persistent store to keep
# track of posted Tweets. The queue is a ordered set that simply holds the
# messages to be posted. The done set uses a ordered set with the timestamp as
# the score so really old Tweets can be cleaned out.

class TwitterTweeter
  include Celluloid
  include Celluloid::Logger

  REDIS_KEY_DONE = 'tweets:done'
  REDIS_KEY_QUEUE = 'tweets:queue'
  REMOVE_OLD_INTERVAL = 86400
  # Adjust times carefully. Because we are posting URLs, we need to watch
  # out for auto account suspensions! (If that happens, sign in and fill out
  # the you've-been-bad captcha to get the account back.)
  PROCESS_QUEUE_INTERVAL = 120
  TWEET_DELAY = 120
  def initialize(redis, twitter_username, twitter_config_filename)
    @redis = ::Redis.new(:url => redis)
    twitter_keys = JSON.load(File.open(twitter_config_filename))

    authenticate_account(twitter_username, twitter_keys)

    @processing = false
    @remove_old_timer = every(REMOVE_OLD_INTERVAL) { remove_old_messages }
    @processing_timer = every(PROCESS_QUEUE_INTERVAL) { process_queue }

    async.process_queue
    async.remove_old_messages
  end

  def authenticate_account(username, keys)
    @client = Twitter::REST::Client.new(keys)

    @client.user(username)

    info "Twitter authentication success."
  end

  def process(job)
    message = nil

    if job.aborted?
      message = "Job #{job.ident} on #{job.url} aborted."
    elsif job.finished?
      message = "Job #{job.ident} on #{job.url} finished."
    elsif job.in_progress?
      message = "Archive job #{job.ident} on #{job.url} by #{job.started_by} started."
    end

    if message
      queue_message(message)
    end
  end

  def queue_message(message)
    return if message_queued?(message)

    debug "Queue message: #{message}"
    @redis.zadd(REDIS_KEY_QUEUE, Time.now.to_i, message)
  end

  def message_queued?(message)
    score = @redis.zscore(REDIS_KEY_QUEUE, message)
    return !score.nil?
  end

  def remove_old_messages
    time =  Time.now.to_i - 2592000

    debug "Removing old messages older than #{time}."
    @redis.zremrangebyscore(REDIS_KEY_DONE, 0, time)
  end

  def process_queue
    return if @processing

    @processing = true

    while true
      message_array = @redis.zrange(REDIS_KEY_QUEUE, 0, 1)

      break if message_array.length == 0

      message = message_array[0]

      post_message(message)
      @redis.zrem(REDIS_KEY_QUEUE, message)
      sleep(TWEET_DELAY)
    end

    @processing = false
  end

  def post_message(message)
    tries_left = 20

    begin
      debug "Attempt to Tweet: #{message}."
      @client.update(message)
      debug "Tweet OK."
    rescue Twitter::Error, StandardError => error
      error "Tweet went wrong: #{error}."

      tries_left -= 1

      if tries_left > 0
        sleep(30)
        retry
      else
        warn "Gave up attempt to Tweet, discarding!"
      end
    end

    @redis.zadd(REDIS_KEY_DONE, Time.now.to_i, message)
  end
end
