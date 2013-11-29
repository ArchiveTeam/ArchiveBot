require 'webmachine'

class History < Webmachine::Resource
  class << self
    attr_accessor :db
  end

  def run_query
    @query ||= self.class.db.history(requested_url, limit, start_at)
  end

  def limit
    100
  end

  def start_at
    request.query['start_at']
  end

  def requested_url
    request.query['url']
  end

  def resource_exists?
    run_query

    @query.success?
  end

  def content_types_provided
    [['application/json', :to_json]]
  end

  def to_json
    run_query

    @query.body.to_json
  end
end
