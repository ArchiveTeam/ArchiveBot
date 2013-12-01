require 'coffee-script'
require 'ember/source'
require 'handlebars/source'
require 'json'
require 'trollop'
require 'uri'
require 'webmachine'
require 'webmachine/sprockets'

require File.expand_path('../../lib/couchdb', __FILE__)
require File.expand_path('../log_actors', __FILE__)
require File.expand_path('../resources/dashboard', __FILE__)
require File.expand_path('../resources/history', __FILE__)
require File.expand_path('../resources/recent', __FILE__)

opts = Trollop.options do
  opt :url, 'URL to bind to', :default => 'http://localhost:4567'
  opt :redis, 'URL of Redis server', :default => ENV['REDIS_URL'] || 'redis://localhost:6379/0'
  opt :log_update_channel, 'Redis pubsub channel for log updates', :default => ENV['LOG_CHANNEL'] || 'updates'
  opt :db, 'URL of CouchDB database', :default => ENV['COUCHDB_URL'] || 'http://localhost:5984/archivebot'
  opt :db_credentials, 'Credentials for CouchDB database (USERNAME:PASSWORD)', :type => String, :default => nil
end

bind_uri = URI.parse(opts[:url])

DB = Couchdb.new(URI(opts[:db]), opts[:db_credentials])
R = Redis.new(:url => opts[:redis])

History.db = DB
Recent.redis = R

App = Webmachine::Application.new do |app|
  sprockets = Sprockets::Environment.new
  sprockets.append_path(File.expand_path('../assets/stylesheets', __FILE__))
  sprockets.append_path(File.expand_path('../assets/javascripts', __FILE__))
  sprockets.append_path(File.expand_path('../assets/fonts', __FILE__))
  sprockets.append_path(File.expand_path('../vendor/assets/fonts', __FILE__))
  sprockets.append_path(File.expand_path('../vendor/assets/javascripts', __FILE__))
  sprockets.append_path(File.expand_path('../vendor/assets/stylesheets', __FILE__))
  sprockets.append_path(File.dirname(Ember::Source.bundled_path_for('ember.js')))
  sprockets.append_path(File.dirname(Handlebars::Source.bundled_path))

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
    add ['logs', 'recent'], Recent
    add ['histories'], History
    add ['assets', '*'], resource
  end
end

LogReceiver.supervise_as :log_receiver, opts[:redis], opts[:log_update_channel]

at_exit do
  Celluloid::Actor[:log_receiver].stop
end

App.run
