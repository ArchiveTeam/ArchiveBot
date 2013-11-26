require 'celluloid'

require File.expand_path('../log_db', __FILE__)

##
# The pipeline stashes log entries in Redis; the cogs and dashboard analyze
# them at some future time (usually not-too-distant).
#
# There's no reason to keep that data indefinitely in Redis, though.
#
# The LogTrimmer removes old log entries to help keep Redis memory usage under
# control.
#
# Theory of operation
# -------------------
#
# Actually, this job just repeatedly calls Job#trim_logs.  See that method for
# its theory of operation.
#
# Job#trim_logs will give us back the trimmed log entries interleaved with
# their scores:
#
#   [["ent1", 1.0], ["ent2", 2.0], ...]
#
# LogDb#add_entries then archives those logs.
class LogTrimmer
  include Celluloid

  def initialize(uri, credentials)
    @log_db = LogDb.new(uri, credentials)
  end

  def process(job)
    entries = job.trim_logs!

    @log_db.add_entries(entries, job)
  end
end
