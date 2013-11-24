require 'celluloid'

class LogAnalyzer
  include Celluloid

  def process(job)
    job.analyze
  end
end
