require 'yajl'
require 'webmachine'

require File.expand_path('../../../lib/job', __FILE__)
require File.expand_path('../../messages', __FILE__)

class Recent < Webmachine::Resource
  class << self
    attr_accessor :redis
  end

  def run_query
    jobs = Job.working(self.class.redis)

    jobs.each_with_object([]) do |j, a|
      a << j.most_recent_log_entries(10).map { |le| LogMessage.new(j, Yajl::Parser.parse(le)) }
    end.flatten
  end

  def content_types_provided
    [['application/json', :to_json]]
  end

  def to_json
    response.headers['Access-Control-Allow-Origin'] = '*'
    run_query.to_json
  end
end
