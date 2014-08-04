require 'yajl'

module Message
  attr_reader :job

  def as_json
    { 'job_data' => job.as_json }
  end

  def to_json(*)
    Yajl::Encoder.encode(as_json)
  end
end

class CompleteMessage
  include Message

  def initialize(job)
    @job = job
  end

  def as_json
    super.merge('type' => 'complete')
  end
end

class LogMessage
  include Message

  def initialize(job, entry)
    @job = job
    @entry = entry
  end

  def as_json
    super.merge(@entry)
  end
end
