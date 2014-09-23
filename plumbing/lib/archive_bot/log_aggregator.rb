require File.expand_path('../../archive_bot', __FILE__)

module ArchiveBot
  ##
  # Merges a job hash into log messages and writes the product as JSON to the
  # given IO stream.  The IO stream is flushed after every write.
  #
  # This is meant to be used as a yajl-ruby parser callback.
  class LogAggregator
    ##
    # The job data as a hash.
    attr_accessor :job

    ##
    # The ident of the job.
    attr_accessor :ident

    ##
    # The IO to write.
    attr_reader :io

    def initialize(io)
      @io = io
    end

    ##
    # Writes merged lines to the given IO.
    #
    # Exceptions raised during write are left for the caller to handle.  In
    # particular, you will probably want to specially handle EPIPE; breaking
    # off a pipe occurs with e.g. head(1) and tail(1).
    def output(obj)
      io.puts Yajl::Encoder.encode(obj.merge('job_data' => job_for_output))
      io.flush
    end

    private

    def job_for_output
      job.merge('ident' => ident)
    end
  end
end
