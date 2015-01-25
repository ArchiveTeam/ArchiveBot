class PipelineInfo
  # The nickname of the pipeline that this job is running on, or
  # nil if the job hasn't been assigned a pipeline ID or
  # #from_pipeline_id hasn't been invoked.
  #
  # If the job has been assigned a pipeline ID and the pipeline
  # record has no nickname, this returns "(anonymous)".
  attr_reader :nickname

  # The pipeline ID.
  attr_reader :id

  def initialize(redis)
    @redis = redis
  end

  def from_pipeline_id(pipeline_id)
    return unless pipeline_id

    h = @redis.hgetall(pipeline_id)

    @nickname = h['nickname'] || '(anonymous)'
    @id = pipeline_id

    self
  end
end
