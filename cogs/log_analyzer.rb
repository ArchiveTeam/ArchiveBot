require File.expand_path('../../lib/log_update_listener', __FILE__)
require File.expand_path('../../lib/job', __FILE__)

class LogAnalyzer < LogUpdateListener
  def on_receive(ident)
    job = ::Job.from_ident(ident, uredis)

    job.analyze if job
  end
end
