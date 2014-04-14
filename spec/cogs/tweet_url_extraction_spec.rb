require 'spec_helper'
require 'vcr'

require 'cogs/tweet_url_extraction'

describe TweetUrlExtraction do
  let(:vessel) do
    Object.new.extend(TweetUrlExtraction)
  end

  describe '#expand_urls' do
    let(:str) do
      '@ATArchiveBot would you kindly get http://t.co/DMTdm3DbKm and http://bit.ly/foobar'
    end

    let(:comma_str) do
      '@ATArchiveBot would you kindly get http://t.co/DMTdm3DbKm, http://bit.ly/foobar'
    end

    around do |example|
      old_logger = Celluloid.logger

      begin
        Celluloid.logger = nil
        example.run
      ensure
        Celluloid.logger = old_logger
      end
    end

    it 'does not modify non-t.co-shortened URLs' do
      VCR.use_cassette('twitter_url_expansion') do
        vessel.expand_urls(str).should include('http://bit.ly/foobar')
      end
    end

    describe 'on t.co URLs' do
      it 'resolves t.co-shortened URLs to their expansions' do
        VCR.use_cassette('twitter_url_expansion') do
          vessel.expand_urls(str).should include('http://www.archiveteam.org/index.php?title=ArchiveBot')
        end
      end

      it 'ignores comma separators' do
        VCR.use_cassette('twitter_url_expansion') do
          vessel.expand_urls(comma_str).should include('http://www.archiveteam.org/index.php?title=ArchiveBot')
        end
      end

      it 'retries failed t.co requests' do
        vessel.expansion_retry_delay = 0.1

        VCR.use_cassette('twitter_url_expansion_with_failure') do
          vessel.expand_urls(str).should include('http://www.archiveteam.org/index.php?title=ArchiveBot')
        end
      end

      it 'does not return unexpandable URLs' do
        vessel.expansion_retries = 0
        vessel.expansion_retry_delay = 0.1

        VCR.use_cassette('twitter_url_expansion_with_failure') do
          vessel.expand_urls(str).length.should == 1
        end
      end
    end
  end
end
