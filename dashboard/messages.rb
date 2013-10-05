require 'json'

module Message
  attr_reader :job

  def as_json
    { 'job_data' => job.as_json }
  end

  def to_json
    as_json.to_json
  end
end

class AbortMessage
  include Message

  def initialize(job)
    @job = job
  end

  def as_json
    super.merge('type' => 'abort')
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
