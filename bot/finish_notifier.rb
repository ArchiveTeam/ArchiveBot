require 'cinch'
require 'json'

require File.expand_path('../finish_message_generation', __FILE__)

##
# Sends messages to tell people when their jobs have finished.
#
# Output
# ------
#
# ArchiveBot users receive messages like this:
#
#   someone: Your job for http://www.example.com has finished. f4pg9usx4j96ki3zczwlczu51
#   someone: n of your jobs have finished.
#
# For aborted jobs, the messages are similar:
#
#   someone: Your job for http://www.example.com was aborted. f4pg9usx4j96ki3zczwlczu51
#   someone: n of your jobs were aborted.
# 
# We coalesce messages to avoid flooding channels with notifications.
#
# Theory of operation
# -------------------
#
# On abort or completion, the Seesaw pipeline inserts a JSON document into the
# finish_notifications list.
#
# This JSON document is the same JSON document that is uploaded with the WARC.
# This JSON document tells us, among other things:
#
# 1. who started the job
# 2. the URL
# 3. whether the job finished with an abort or complete
#
# Every CYCLE seconds, CompletionNotifier pops each document out of the list,
# analyzes it, and builds up a set of messages to send.
class FinishNotifier
  include Cinch::Plugin
  include FinishMessageGeneration

  CYCLE = 30  # seconds

  timer CYCLE, method: :announce_completions

  def announce_completions
    latest = get_latest_completions(config[:redis])
    return if latest.empty?
    
    latest.each do |channel, msgs|
      msgs.each { |msg| Channel(channel).send(msg) }
    end
  end

  private

  def get_latest_completions(redis)
    infos = []

    loop do
      data = redis.lpop('finish_notifications')
      break unless data

      infos << JSON.parse(data)
    end

    generate_messages(infos)
  end
end
