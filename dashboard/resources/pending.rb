class Pending < Webmachine::Resource
  class << self
    attr_accessor :redis
  end

  def content_types_provided
    [
      ['text/plain', :to_text]
    ]
  end

  def to_text
    seen = {}

    # Collect queues
    self.class.redis.scan_each(:match => "pending*") do |queue|
      next if seen[queue]
      seen[queue] = true
    end

    # "pending" sorts before "pending-*" and "pending:*", and "-" sorts before ":", so no special treatment needed to get the desired sorting.

    buffer = []
    seen.keys.sort_by(&:downcase).each do |queue|
      b = []
      b << queue
      self.class.redis.lrange(queue, 0, -1).each do |jobid|
        b << "  " + jobid
      end
      buffer << b.join("\n")
    end

    buffer.join("\n\n")
  end
end
