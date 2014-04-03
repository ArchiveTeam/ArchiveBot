require 'celluloid'
require 'json'
require 'logger'
require 'net/http'

require File.expand_path('../../../archive_url', __FILE__)
require File.expand_path('../fetcher', __FILE__)
require File.expand_path('../../internet_archive', __FILE__)

module ArchiveUrlGenerators::InternetArchive
  ##
  # Given a set of URLs from ArchiveBot GO! packs, generates archive URL
  # records.
  class Generator
    attr_reader :logger
    attr_reader :fetcher

    def initialize(logger = ::Logger.new($stderr))
      @logger = logger
      @fetcher = Fetcher.pool(size: 8, args: [logger])
    end

    def archive_urls(urls)
      # We look for pairs of URLs matching the form
      #
      #   BASENAME.warc.gz
      #   BASENAME.json
      #
      # For each pair that's found, we download and parse the JSON and do a
      # HEAD request on the warc.gz to discover its size.  We then generate a
      # hash of the form
      #
      #   { archive_url: BASENAME.warc.gz,
      #     url: (url),
      #     queued_at: (queued_at),
      #     file_size: (WARC size)
      #   }
      #
      # If the JSON contains an "ident" field, we include that in the archive
      # URL hash too; however, the ident is not necessary.

      is_warc_gz = /\.warc\.gz\Z/
      is_json = /\.json\Z/
      accepted_extensions = %r{#{is_warc_gz}|#{is_json}}

      basename = ->(k) do
        k.sub(%r{^/}, '').sub(accepted_extensions, '')
      end

      mapping = urls.each_with_object({}) do |url, h|
        next unless url =~ accepted_extensions

        bn = basename.(url)
        h[bn] ||= UrlSet.new(logger)

        if url =~ is_warc_gz
          h[bn].warc_url = url
        elsif url =~ is_json
          h[bn].json_url = url
        end
      end

      # Reject incomplete sets.
      ok, not_ok = mapping.partition { |bn, url_set| url_set.complete? }

      if !not_ok.empty?
        logger.warn "Discarded #{not_ok.length} incomplete URL pairs"
      end

      # Start fetch.
      ok.each { |bn, url_set| url_set.fetch_data(fetcher) }

      erroneous = false

      # Read results.
      archive_urls = ok.each_with_object([]) do |(bn, url_set), a|
        if url_set.fetch_ok?
          ok = url_set.parse
          next unless ok

          warc_size = url_set.warc_size
          json = url_set.json

          record = ArchiveUrl.new(
            url: json['url'],
            queued_at: json['queued_at'],
            ident: json['ident'],
            file_size: warc_size,
            archive_url: url_set.warc_url
          )

          if record.valid?
            a << record
          else
            error "ArchiveUrl for #{url_set.warc_url} is invalid; skipping import"
          end
        else
          erroneous = true
        end
      end

      [archive_urls, erroneous]
    end
  end

  class UrlSet < Struct.new(:warc_url, :json_url)
    attr_reader :json
    attr_reader :warc_size
    attr_reader :logger

    def initialize(logger)
      super()

      @logger = logger
    end

    def complete?
      warc_url && json_url
    end

    def fetch_data(fetcher)
      @json_future = fetcher.future(:fetch, json_url)
      @warc_future = fetcher.future(:head, warc_url)
    end

    def fetch_ok?
      [@json_future.value, @warc_future.value].all? do |resp|
        Net::HTTPSuccess === resp
      end
    end

    def parse
      json_resp = @json_future.value

      begin
        @json = JSON.parse(json_resp.body)
      rescue JSON::ParserError
        logger.error "#{json_url} contains invalid JSON"
        nil
      end
    end
    
    def warc_size
      resp = @warc_future.value

      if fetch_ok?
        resp['Content-Length']
      end
    end
  end
end
