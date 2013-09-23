require File.expand_path('../log_update_listener', __FILE__)
require File.expand_path('../job', __FILE__)

class LogAnalyzer < LogUpdateListener
  def on_receive(ident)
    job = ::Job.from_ident(ident, uredis)

    job.analyze if job
  end
end
