require 'json'
require 'webmachine'

class Status < Webmachine::Resource
  class << self
    attr_accessor :redis
  end

  def get_status_hash
    pendingothers = Hash.new
    redis = self.class.redis
    redis.scan_each(:match => "pending:*") { |key| pendingothers[key] = redis.llen(key) }
    {
      'pending' => redis.llen('pending'),
      'pending-ao' => redis.llen('pending-ao'),
      'pending-others' => pendingothers.values.inject(0, :+), #TODO: Replace with values.sum for Ruby 2.4+
      'pending-others-details' => pendingothers,
      'working' => redis.llen('working'),
      'completed' => Integer(redis.get('jobs_completed') || 0),
      'aborted' => Integer(redis.get('jobs_aborted') || 0),
      'failed' => Integer(redis.get('jobs_failed') || 0),
    }
  end

  def content_types_provided
    [
      ['application/json', :to_json],
    ]
  end

  def to_json
    response.headers['Access-Control-Allow-Origin'] = '*'
    get_status_hash.to_json
  end
end
