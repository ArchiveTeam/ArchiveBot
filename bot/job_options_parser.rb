require 'shellwords'
require 'trollop'

class JobOptionsParser
  def initialize
    @parser = Trollop::Parser.new do
      opt :phantomjs, 'Use PhantomJS grabber'
      opt :phantomjs_scroll, 'Number of times to scroll a page', :type => :integer
      opt :phantomjs_wait, 'Seconds to wait between page interactions', :type => :float
      opt :no_phantomjs_smart_scroll, 'Always scroll the page to the specified scroll count'
      opt :no_offsite_links, 'Do not fetch offsite links'
      opt :youtube_dl, 'Use youtube-dl on grabbed pages'
      opt :ignore_sets, 'Ignore sets to apply', :type => :string
      opt :pipeline, 'Run job on this pipeline', :type => :string
      opt :user_agent_alias, 'Use this user agent for the job', :type => :string
      opt :explain, 'Short note explaining archive purpose', :type => :string
      opt :delay, 'inter-request delay, in milliseconds', :type => :integer
      opt :concurrency, 'number of workers', :type => :integer
    end
  end

  def parse(str)
    begin
      args = Shellwords.split((str || '')).map do |a|
        b=a.split('=')
        b[0] = (case b[0]
               when '--ignoresets','--ignore_sets','--ignoreset','--ignore-set','--ignore_set','--ig-set','--igset' then '--ignore-sets'
               when '--nooffsitelinks','--no-offsite','--nooffsite' then '--no-offsite-links'
               when '--useragentalias','--user-agent','--useragent' then '--user-agent-alias'
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
