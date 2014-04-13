require 'celluloid'
require 'json'
require 'twitter'

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

  def initialize(db_uri, db_credentials, twitter_config_filename)
    @config = JSON.load(File.read(twitter_config_filename))
    @db = Couchdb.new(db_uri, db_credentials)

    async.start
  end

  def start
    username = config.delete('username')
    trigger = "#{username} would you kindly"

    client = Twitter::Streaming::Client.new(config)

    client.filter(track: trigger) do |object|
      if object.is_a?(Twitter::Tweet)
        info "Received Tweet: #{object.text}"
      end
    end
  end
end
