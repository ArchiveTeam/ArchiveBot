require 'json'
require 'webmachine'

require File.expand_path('../../../lib/job', __FILE__)
require File.expand_path('../../messages', __FILE__)

class Recent < Webmachine::Resource
  class << self
    attr_accessor :redis
  end

  def run_query(count=10)
    jobs = Job.working(self.class.redis)

    jobs.each_with_object([]) do |j, a|
      if j #TODO: Why is this necessary?
        a << j.most_recent_log_entries(count).map { |le| LogMessage.new(j, JSON.parse(le)) }
      end
    end.flatten
  end

  def content_types_provided
    [
      ['application/json', :to_json],
      ['text/html', :to_html]
    ]
  end

  def encodings_provided
    {'gzip' => :encode_gzip, 'deflate' => :encode_deflate, 'identity' => :encode_identity}
  end

  def to_json
    response.headers['Access-Control-Allow-Origin'] = '*'
    count = [[request.query['count'] ? request.query['count'].to_i : 10, 10].min, 1].max
    run_query(count).to_json
  end

  def to_html
    File.read(File.expand_path('../../recent.html', __FILE__))
  end
end
