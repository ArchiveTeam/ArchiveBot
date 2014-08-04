require 'yajl'
require 'logger'
require 'net/http'
require 'rack'

require File.expand_path('../../internet_archive', __FILE__)

module ArchiveUrlGenerators::InternetArchive
  ##
  # Locates ArchiveBot GO! packs with an update date greater than or equal to a
  # given threshold.
  #
  class PackFinder
    include Enumerable

    attr_reader :limit
    attr_reader :threshold
    attr_reader :logger

    def initialize(threshold = nil, limit = 1000, logger = ::Logger.new($stderr))
      @limit = limit
      @logger = logger
      @threshold = threshold
    end

    ##
    # Runs a search against IA for GO! packs.
    #
    # If the search returns a successful response, yields each found URL in
    # ascending addeddate order.  If the search is not successful, raises an
    # exception.
    def each
      uri = search_uri(threshold)
      resp = Net::HTTP.get_response(uri)
      logger.info "GET #{uri}: #{resp.code}"

      # If we don't get a successful response, we can't really return anything
      # useful.  Bail.
      unless Net::HTTPSuccess === resp
        raise "Expected 2xx from IA advanced search, got #{resp.code} instead"
      end

      json = Yajl::Parser.parse(resp.body)
      docs = json['response']['docs']

      docs.each do |d|
        yield pack_url(d['identifier'])
      end
    end

    private

    def pack_url(pack_identifier)
      "https://archive.org/details/#{pack_identifier}?output=json"
    end

    def search_uri(threshold)
      query = [
        'title:(archivebot go pack)',
        'collection:(archivebot)'
      ]

      if threshold
        # We get one sort of dates back from our pack search, but we need to
        # feed a different format into IA.
        #
        # Additionally, we want to get everything *after* the given threshold,
        # but not *including* it.  Lucene supports {} notation for exclusive
        # ranges, but IA's search engine doesn't.  Workaround: add one second
        # to the threshold.
        begin
          date = (Time.parse(threshold) + 1).utc.strftime('%Y-%m-%dT%H:%M:%SZ')
          query << "addeddate:[#{date} TO null]"
        rescue ArgumentError => e
          logger.error "#{threshold} could not be parsed as a time; skipping threshold"
        end
      end
        
      uri = URI.parse('https://archive.org/advancedsearch.php')

      params = {
        'q' => query.join(' AND '),
        'output' => 'json',

        # Lucene's high-level API doesn't expose a "give me all results"
        # option.
        'rows' => limit
      }

      uri.tap do |u|
        u.query = Rack::Utils.build_query(params)

        # We don't want fl[] to be escaped, but Rack::Utils.build_query won't
        # append a [] if we pass fl => [stuff] to it.
        u.query += "&fl[]=identifier&sort[]=addeddate+asc"
      end
    end
  end
end
