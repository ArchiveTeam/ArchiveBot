require 'json'
require 'trollop'
require 'uri'
require 'webmachine'
require 'webmachine/sprockets'

require File.expand_path('../../lib/shared_config', __FILE__)
require File.expand_path('../log_actors', __FILE__)
require File.expand_path('../resources/dashboard', __FILE__)
require File.expand_path('../resources/feed', __FILE__)
require File.expand_path('../resources/pipeline', __FILE__)
require File.expand_path('../resources/recent', __FILE__)

opts = Trollop.options do
  opt :url, 'URL to bind to', :default => 'http://localhost:4567'
  opt :redis, 'URL of Redis server', :default => ENV['REDIS_URL'] || 'redis://localhost:6379/0'
end

bind_uri = URI.parse(opts[:url])

R = Redis.new(:url => opts[:redis], :driver => :hiredis)

Pipeline.redis = R
Recent.redis = R
Feed.redis = R

App = Webmachine::Application.new do |app|
  sprockets = Sprockets::Environment.new
  sprockets.append_path(File.expand_path('../assets/images', __FILE__))
  sprockets.append_path(File.expand_path('../assets/scripts', __FILE__))

  resource = Webmachine::Sprockets.resource_for(sprockets)

  app.configure do |config|
    config.ip = bind_uri.host
    config.port = bind_uri.port
    config.adapter = :Reel
    config.adapter_options[:websocket_handler] = proc do |ws|
      if ws.url == '/stream'
        LogClient.new(ws)
      else
        ws.close
      end
    end
  end

  app.routes do
    add [], Dashboard
    add ['beta'], DashboardBeta
    add ['logs', 'recent'], Recent
    add ['pipelines'], Pipeline
    add ['assets', '*'], resource
    add ['feed', 'archivebot.rss'], RssFeed
    add ['feed', 'archivebot.atom'], AtomFeed
    add ['feed'], Feed
  end
end

at_exit do
  Celluloid::Actor[:log_receiver].stop
end

class Broadcaster
  include Celluloid
  include Celluloid::Notifications

  def initialize(channel, input)
    @channel = channel
    @input = input

    async.slurp
  end

  def broadcast(msg)
    publish(@channel, msg)
  end

  def slurp
    @input.each_line { |l| broadcast(l.chomp) }
  end
end

Broadcaster.supervise_as :broadcaster, SharedConfig.log_channel, $stdin

App.run
