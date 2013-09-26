require 'coffee-script'
require 'json'
require 'trollop'
require 'uri'
require 'webmachine'
require 'webmachine/sprockets'

require File.expand_path('../../history_db', __FILE__)
require File.expand_path('../log_actors', __FILE__)

opts = Trollop.options do
  opt :url, 'URL to bind to', :default => 'http://localhost:4567'
  opt :redis, 'URL of Redis server', :default => ENV['REDIS_URL'] || 'redis://localhost:6379/0'
  opt :log_update_channel, 'Redis pubsub channel for log updates', :default => ENV['LOG_CHANNEL'] || 'updates'
  opt :db, 'URL of CouchDB history database', :default => ENV['COUCHDB_URL'] || 'http://localhost:5984/archivebot_history'
  opt :db_credentials, 'Credentials for history database (USERNAME:PASSWORD)', :type => String, :default => nil
end

bind_uri = URI.parse(opts[:url])

DB = HistoryDb.new(URI(opts[:db]), opts[:db_credentials])

class History < Webmachine::Resource
  def run_query
    @query ||= DB.history(requested_url, limit, start_at)
  end

  def limit
    100
  end

  def start_at
    request.query['start_at']
  end

  def requested_url
    URI.decode(request.path_tokens.join('/'))
  end

  def resource_exists?
    run_query

    @query.success?
  end

  def content_types_provided
    [['application/json', :to_json]]
  end

  def to_json
    run_query

    @query.body.to_json
  end
end

class Dashboard < Webmachine::Resource
  def to_html
    File.read(File.expand_path('../dashboard.html', __FILE__))
  end
end

App = Webmachine::Application.new do |app|
  sprockets = Sprockets::Environment.new
  sprockets.append_path(File.expand_path('../assets/stylesheets', __FILE__))
  sprockets.append_path(File.expand_path('../assets/javascripts', __FILE__))
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
    add ['histories', '*'], History
    add ['assets', '*'], resource
  end
end

LogReceiver.supervise_as :log_receiver, opts[:redis], opts[:log_update_channel]

at_exit do
  Celluloid::Actor[:log_receiver].stop
end

App.run
