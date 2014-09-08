require 'webmachine'

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

##
# SCANs for pipeline keys.  When it finds one it hasn't yet seen, performs an
# HGETALL on that key and yields the resulting hash.
class PipelineCollection
  include Enumerable

  attr_reader :redis

  def initialize(redis)
   @redis = redis
  end

  def each
    return to_enum unless block_given?

    cursor = 0
    seen = {}

    loop do
      cursor, keys = redis.scan(cursor, match: 'pipeline:*')

      keys.each do |k|
        next if seen[k]

        seen[k] = true
        yield redis.hgetall(k)
      end

      break if cursor.to_i == 0
    end
  end
end
