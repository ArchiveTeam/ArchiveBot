require 'json'
require 'net/http/persistent'
require 'uri'
require 'zlib'

module ArchiveUrlDiscovery
  ##
  # Finds URLs for ArchiveBot-generated WARCs on archive.org.
  #
  #
  # Theory of operation
  # -------------------
  #
  # This crawler is fairly elaborate.  It downloads the first 32 kB of a
  # gzip-compressed WARC, which is almost always sufficient to get the first
  # record of an ArchiveBot-generated WARC.  The first record contains an
  # "archivebot-job-ident" field, which we can read.
  #
  # From ArchiveBot's JSON files, we read job queuing time and abort status,
  # which are used to match the archive URL to a job.
  #
  #
  # A bit of self-deprecation
  # -------------------------
  #
  # For quite some time, ArchiveBot only wrote its job identifiers into the
  # WARCs.  Later on, the ArchiveBot pipeline was changed to generate JSON
  # files to summarize a WARC's contents.
  #
  # But the job ident never made it into the JSON.  The rationale? The job
  # ident is an ArchiveBot-specific field, and is of no interest to external
  # parties.  What I didn't count on is that ArchiveBot would become its own
  # "external party".
  #
  # Future versions of the pipeline will likely throw the job ident into the
  # JSON file so I can save myself this torture, but for now I must deal with
  # the consequences of my decisions.
  class IaUrlGenerator
    attr_reader :json
    attr_reader :http
    attr_reader :logger

    WARC_EXT = /\.warc\.gz$/
    JSON_EXT = /\.json$/

    def initialize(json, logger)
      @json = json
      @http = Net::HTTP::Persistent.new('ArchiveBot')
      @logger = logger
    end

    def run
      server = json['server']
      dir = json['dir']
      results = {}

      json['files'].keys.each do |k|
        # Build the item's URL.
        uri = URI("https://#{server}#{dir}#{k}")

        # Figure out the job basename.  We use this to coalesce data from the
        # WARC and the JSON.
        #
        # FYI: File.extname won't properly identify .warc.gz as an extension,
        # which is why we do this regex alternation stuff.
        basename = k.sub(%r{^/}, '').sub(%r{#{WARC_EXT}|#{JSON_EXT}}, '')

        # Get the data.
        doc = case k
              when WARC_EXT; process_warc(uri)
              when JSON_EXT; process_json(uri)
              end

        # Coalesce.
        if doc
          results[basename] ||= {}
          results[basename].update(doc)
        end
      end

      results.values
    end

    private

    def process_warc(uri)
      resp = get(uri, 0..31999)
      return unless Net::HTTPSuccess === resp

      reader = Zlib::GzipReader.new(StringIO.new(resp.body))
      buf = reader.each_byte.with_object("") { |byte, buf| buf << byte }

      if buf =~ /^archivebot-job-ident: ([^\s]+)/
        { 'ident' => $1, 'archive_url' => uri.to_s }
      else
        {}
      end
    end

    def process_json(uri)
      resp = get(uri)
      return unless Net::HTTPSuccess === resp

      json = JSON.parse(resp.body)

      { 'queued_at' => json['queued_at'].to_i, 'aborted' => json['aborted'] }
    end

    def get(uri, range = nil)
      req = Net::HTTP::Get.new(uri.request_uri)
      req.range = range if range
      http.request(uri, req).tap do |resp|
        logger.info "GET #{uri}: #{resp.code}"
      end
    end
  end
end

# Standalone executable mode.
#
# Run it like this:
#
#   cat some-manifest.json | ruby ia_url_generator.rb
if $0 == __FILE__
  require 'logger'

  doc = JSON.parse($stdin.read)

  results = ArchiveUrlDiscovery::IaUrlGenerator.new(doc, Logger.new($stderr)).run
  puts results.to_json
end
