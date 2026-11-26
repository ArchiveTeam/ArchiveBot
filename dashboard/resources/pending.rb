class Pending < Webmachine::Resource
  class << self
    attr_accessor :redis
  end

  def get_queues
    seen = {}

    # Collect queues
    self.class.redis.scan_each(:match => "pending*") do |queue|
      next if seen[queue]
      seen[queue] = true
    end

    # "pending" sorts before "pending-*" and "pending:*", and "-" sorts before ":", so no special treatment needed to get the desired sorting.

    results = {}
    seen.keys.sort_by(&:downcase).each do |queue|
      results[queue] = []

      idents = self.class.redis.lrange(queue, 0, -1).reverse

      urls = self.class.redis.pipelined do
        idents.each { |ident| self.class.redis.hget(ident, 'url') }
      end

      idents.zip(urls).each.with_index do |(ident, url), i|
        results[queue] << {"url": url, "ident": ident}
      end
    end

    return results
  end

  def content_types_provided
    [
      ['application/json', :to_json],
      ['text/plain', :to_text]
    ]
  end

  def to_text

    buffer = []
    get_queues.each do |queue, jobs|
      b = []
      b << queue

      i = 0
      jobs.each do |job|
        i += 1
        b << "  #{i}. #{job[:url]} (#{job[:ident]})"
      end

      buffer << b.join("\n")
    end

    buffer.join("\n\n")
  end

  def to_json
    response.headers['Access-Control-Allow-Origin'] = '*'
    get_queues.to_json
  end

end
