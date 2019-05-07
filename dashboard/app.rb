require 'json'
require 'redis'
require 'trollop'
require 'uri'
require 'webmachine'
require 'webmachine/sprockets'

require File.expand_path('../../lib/shared_config', __FILE__)
require File.expand_path('../resources/dashboard', __FILE__)
require File.expand_path('../resources/feed', __FILE__)
require File.expand_path('../resources/pipeline', __FILE__)
require File.expand_path('../resources/recent', __FILE__)
require File.expand_path('../resources/ignores', __FILE__)
require File.expand_path('../resources/pending', __FILE__)

opts = Trollop.options do
  opt :url, 'URL to bind to', :default => 'http://localhost:4567'
  opt :redis, 'URL of Redis server', :default => ENV['REDIS_URL'] || 'redis://localhost:6379/0'
end

bind_uri = URI.parse(opts[:url])

R = Redis.new(:url => opts[:redis], :driver => :hiredis)

Pipeline.redis = R
Ignores.redis = R
Recent.redis = R
Pending.redis = R
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
  end

  app.routes do
    add [], Dashboard
    add ['beta'], DashboardBeta
    add ['3'], DashboardBeta
    add ['logs', 'recent'], Recent
    add ['ignores', '*'], Ignores
    add ['pipelines', '*'], Pipeline
    add ['pending'], Pending
    add ['assets', '*'], resource
    add ['feed', 'archivebot.rss'], RssFeed
    add ['feed', 'archivebot.atom'], AtomFeed
    add ['feed'], Feed
  end
end

App.run
