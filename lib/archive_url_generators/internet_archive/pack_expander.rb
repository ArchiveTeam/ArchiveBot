require 'celluloid'
require 'json'
require 'logger'
require 'net/http'
require 'time'
require 'uri'

require File.expand_path('../fetcher', __FILE__)
require File.expand_path('../../internet_archive', __FILE__)

module ArchiveUrlGenerators::InternetArchive
  ##
  # Expands a list of packs into (WARC, JSON) pairs.
  class PackExpander
    include Enumerable

    attr_reader :logger
    attr_reader :fetcher

    def initialize(pack_urls, logger = ::Logger.new($stderr))
      @pack_urls = pack_urls
      @logger = logger
      @fetcher = Fetcher.pool(size: 4, args: [logger])
    end

    ##
    # Given a list of pack URLs, attempts to expand each one to a list of URLs
    # to its component files.
    #
    # For each pack URL, yields a (pack_url, resp, ok, addeddate, urls) tuple.
    # Tuples are yielded in the same order as their respective pack URL.
    # 
    #
    # Tuple contents
    # --------------
    #
    # The addeddate is the latest addeddate for the pack.  The response is the
    # HTTP response that generated the corresponding URLs; therefore, the block
    # may be invoked more than once.
    #
    # For non-success responses, urls will be [] and addeddate will be nil.
    def each
      pairs = @pack_urls.map { |pu| [pu, fetcher.future(:fetch, pu)] }

      pairs.each do |pu, f|
        resp = f.value

        if Net::HTTPSuccess === resp
          json = JSON.parse(resp.body)

          yield pu, resp, true, latest_addeddate(json), urls_in_json(json)
        else
          yield pu, resp, false, nil, []
        end
      end
    end

    private

    ##
    # Returns the latest addeddate for a pack.
    #
    # IA items have multiple date fields, and each date field may have multiple
    # values.  If there are multiple addeddates, we return the latest one.
    def latest_addeddate(json)
      metadata = json['metadata']

      metadata['addeddate'].map do |date|
        Time.parse(date) rescue nil
      end.compact.sort.last
    end

    def urls_in_json(json)
      # We get the server in the JSON, but we use archive.org's download
      # redirector so that links keep working even if IA decides to shuffle
      # around data.
      dir = json['dir']
      metadata = json['metadata']
      identifier = metadata['identifier'].first
     
      json['files'].keys.map { |k| "https://archive.org/download/#{identifier}#{k}" }
    end
  end
end
