require 'webmachine'

class History < Webmachine::Resource
  class << self
    attr_accessor :db
  end

  def run_query
    @query ||= self.class.db.history(requested_url)
  end

  def requested_url
    request.query['url']
  end

  def content_types_provided
    [['application/json', :to_json]]
  end

  def to_json
    run_query

    { 'rows' => @query }.to_json
  end
end
