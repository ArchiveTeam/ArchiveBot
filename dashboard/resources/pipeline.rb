require 'webmachine'

require File.expand_path('../../../lib/pipeline_collection', __FILE__)

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
    { 'pipelines' => PipelineCollection.new(self.class.redis).to_a }.to_json
  end

  def to_html
    File.read(File.expand_path('../../pipeline.html', __FILE__))
  end
end
