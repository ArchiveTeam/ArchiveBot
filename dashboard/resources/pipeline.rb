require 'webmachine'

##
# A PublicPipelineRecord differs from a plain pipeline record in that it throws
# away potentially confidential information.
class PublicPipelineRecord
  attr_reader :hash
  def initialize(hash)
    @hash = hash
  end

  def to_json(*)
    {
      'mem_usage' => hash['mem_usage'],
      'disk_usage' => hash['disk_usage'],
      'pipeline_id' => hash['id'],
      'version' => hash['version'],
      'timestamp' => hash['ts'],
    }.to_json
  end
end

class Pipeline < Webmachine::Resource
  class << self
    attr_accessor :redis
  end

  def content_types_provided
    [
      ['application/json', :to_json],
      ['text/html', :to_html]
    ]
  end

  def to_json
    run_query.to_json
  end

  def to_html
    File.read(File.expand_path('../../pipeline.html', __FILE__))
  end

  def run_query
    r = self.class.redis

    pipeline_ids = r.smembers('pipelines')
    pipeline_data = r.pipelined do
      pipeline_ids.map { |p_id| r.hgetall(p_id) }
    end

    { 'pipelines' => pipeline_data.map { |pd| PublicPipelineRecord.new(pd) } }
  end
end
