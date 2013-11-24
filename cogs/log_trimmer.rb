require 'celluloid'

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
# Job#trim_logs will give us back the trimmed log entries as a set of strings.
#
# Eventually, this job will shove log results into a CouchDB database.
class LogTrimmer
  include Celluloid

  def process(job)
    job.trim_logs!
  end
end
