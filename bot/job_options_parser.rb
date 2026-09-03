require 'shellwords'
require 'trollop'

class JobOptionsParser
  def initialize
    @parser = Trollop::Parser.new do
      opt :no_offsite_links, 'Do not fetch offsite links'
      opt :no_cookies, 'Do not use cookies'
      opt :youtube_dl, 'Use youtube-dl on grabbed pages'
      opt :ignore_sets, 'Ignore sets to apply', :type => :string
      opt :pipeline, 'Run job on this pipeline', :type => :string
      opt :user_agent_alias, 'Use this user agent for the job', :type => :string
      opt :explain, 'Short note explaining archive purpose', :type => :string
      opt :delay, 'inter-request delay, in milliseconds', :type => :integer
      opt :concurrency, 'number of workers', :type => :integer
      opt :large, 'Job includes many large (>500MB) files'
    end
  end

  def parse(str)
    begin
      args = Shellwords.split((str || '')).map do |a|
        b=a.split('=')
        b[0] = (case b[0]
               when '--ignoresets','--ignore_sets','--ignoreset','--ignore-set','--ignore_set','--ig-set','--igset' then '--ignore-sets'
               when '--nooffsitelinks','--no-offsite','--nooffsite' then '--no-offsite-links'
               when '--nocookies' then '--no-cookies'
               when '--useragentalias','--user-agent','--useragent' then '--user-agent-alias'
               when '--concurrent' then '--concurrency'
               when '--reason' then '--explain'
               else b[0]
               end)
        b.join('=')
      end
      @parser.parse(args).tap do |h|
        if h[:ignore_sets]
          h[:ignore_sets] = h[:ignore_sets].split(',')
        end
      end
    rescue Trollop::CommandlineError => e
      raise UnknownOptionError, e.message
    end
  end
  
  class UnknownOptionError < StandardError
  end
end
