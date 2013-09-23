require 'reel'
require 'trollop'
require 'uri'

require File.expand_path('../log_actors', __FILE__)

opts = Trollop.options do
  opt :url, 'URL to bind to', :default => 'http://localhost:4567'
  opt :redis, 'URL of Redis server', :default => ENV['REDIS_URL'] || 'redis://localhost:6379/0'
  opt :log_update_channel, 'Redis pubsub channel for log updates', :default => ENV['LOG_CHANNEL'] || 'updates'
end

bind_uri = URI.parse(opts[:url])

# The webapp.
class Webapp < Reel::Server
  attr_reader :dashboard_html

  def initialize(uri)
    @dashboard_html = File.read(File.expand_path('../dashboard.html', __FILE__)).freeze

    super uri.host, uri.port, &method(:on_connection)
  end

  def on_connection(conn)
    while req = conn.request
      if req.websocket?
        conn.detach

        route_websocket(req.websocket)
        return
      else
        if req.url == '/'
          return show_dashboard(conn)
        else
          conn.respond :not_found, 'Not found'
        end
      end
    end
  end

  def route_websocket(socket)
    if socket.url == '/stream'
      LogClient.new(socket)
    else
      info "Invalid WebSocket request: #{socket.url}"
      socket.close
    end
  end

  def show_dashboard(conn)
    conn.respond :ok, dashboard_html
  end
end

LogReceiver.supervise_as :log_receiver, opts[:redis], opts[:log_update_channel]
Webapp.supervise_as :webapp, bind_uri

at_exit do
  Celluloid::Actor[:log_receiver].stop
end

sleep
