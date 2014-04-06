require 'trollop'

class JobOptionsParser
  def initialize
    @parser = Trollop::Parser.new do
      opt :js, 'Use PhantomJS grabber'
      opt :ignore_sets, 'Ignore sets to apply', :type => :string
      opt :pipeline, 'Run job on this pipeline', :type => :string
    end
  end

  def parse(str)
    begin
      @parser.parse(str.split(/\s+/)).tap do |h|
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
