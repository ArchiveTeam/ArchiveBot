require 'celluloid'
require 'net/http/persistent'

require File.expand_path('../../internet_archive', __FILE__)

module ArchiveUrlGenerators::InternetArchive
  class Fetcher
    include Celluloid

    attr_reader :http
    attr_reader :logger

    def initialize(logger)
      @http = Net::HTTP::Persistent.new(self.class.name)
      @logger = logger
    end

    def head(url)
      uri = URI(url)
      req = Net::HTTP::Head.new(uri.request_uri)

      resp = http.request(uri, req)

      if Net::HTTPRedirection === resp
        logger.debug "HEAD #{uri}: #{resp.code} -> #{resp['Location']}"
        follow_redirect('head', uri, URI(resp['Location']))
      else
        logger.debug "HEAD #{uri}: #{resp.code}"
        resp
      end
    end

    def fetch(url)
      uri = URI(url)
      req = Net::HTTP::Get.new(uri.request_uri)

      resp = http.request(uri, req)

      if Net::HTTPRedirection === resp
        logger.debug "GET #{uri}: #{resp.code} -> #{resp['Location']}"
        follow_redirect('get', uri, URI(resp['Location']))
      else
        logger.debug "GET #{uri}: #{resp.code}"
        resp
      end
    end

    alias_method :get, :fetch

    private

    def follow_redirect(method, source, dest)
      if dest.absolute?
        send(method, dest)
      else
        send(method, source.merge(dest))
      end
    end
  end
end
