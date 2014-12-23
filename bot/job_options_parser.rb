require 'trollop'

class JobOptionsParser
  def initialize
    @parser = Trollop::Parser.new do
      opt :phantomjs, 'Use PhantomJS grabber'
      opt :phantomjs_scroll, 'Number of times to scroll a page', :type => :integer
      opt :phantomjs_wait, 'Seconds to wait between page interactions', :type => :float
      opt :no_phantomjs_smart_scroll, 'Always scroll the page to the specified scroll count'
      opt :offsite_links, 'Also fetch offsite links'
      opt :ignore_sets, 'Ignore sets to apply', :type => :string
      opt :pipeline, 'Run job on this pipeline', :type => :string
      opt :user_agent_alias, 'Use this user agent for the job', :type => :string
    end
  end

  def parse(str)
    begin
      @parser.parse((str || '').split(/\s+/)).tap do |h|
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
