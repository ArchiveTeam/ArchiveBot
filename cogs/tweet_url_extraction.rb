require 'celluloid'
require 'net/http'
require 'uri'

module TweetUrlExtraction
  ##
  # Amount of time to wait between URL expansion retries, in seconds.  If not
  # set, defaults to 5 seconds.
  attr_accessor :expansion_retry_delay

  ##
  # Number of times to retry tweet URL expansion.  Defaults to 10.
  attr_accessor :expansion_retries

  ##
  # Extracts and expands URLs out of a tweet.
  #
  # URLs with host t.co (i.e. Twitter's URL shortener) will be expanded.  Other
  # URLs will be passed on as-is.
  def expand_urls(str)
    # Commas usually immediately follow URLs.  These cause us grief, so we
    # ignore them.
    urls = URI.extract(str.gsub(',', ''))
    retries = self.expansion_retries || 10
    retry_delay = self.expansion_retry_delay || 5
    resolvers = UrlExpander.pool(size: 4, args: [retries, retry_delay])

    begin
      futures = urls.map do |u|
        URI(u).host == 't.co' ? resolvers.future(:expand, u) : u
      end

      futures.map! do |f|
        f.respond_to?(:value) ? f.value : f
      end.compact
    ensure
      resolvers.terminate
    end
  end

  private

  class UnexpectedResponseError < StandardError
  end

  class UrlExpander
    include Celluloid
    include Celluloid::Logger

    attr_reader :retries
    attr_reader :retry_delay

    def initialize(retries, retry_delay)
      @retry_delay = retry_delay
      @retries = retries
    end

    def expand(url, tries = 1)
      begin
        resp = Net::HTTP.get_response(URI(url))

        if Net::HTTPRedirection === resp
          resp['Location']
        else
          raise UnexpectedResponseError, "Expected 3xx, got #{resp.code}"
        end
      rescue => e
        if tries > retries
          error "Too many errors expanding #{url}.  Ignoring URL."
          nil
        else
          error "Exception raised while expanding #{url}: #{e.inspect}.  Retrying in #{retry_delay} seconds."
          sleep retry_delay
          expand(url, tries + 1)
        end
      end
    end
  end
end
