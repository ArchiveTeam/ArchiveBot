class Ignores < Webmachine::Resource
  class << self
    attr_accessor :redis
  end

  def content_types_provided
    [
      ['text/plain', :to_text]
    ]
  end

  def to_text
    buffer = []

    keys.each do |key|
      self.class.redis.sscan_each("#{key}_ignores", count: 100) do |ignore|
        buffer << [key, ignore]
      end
    end

    buffer.sort_by!(&:last).map! { |p| p.join("\t") }.join("\n")
  end

  private

  def keys
    request.path_tokens.last.split(',')
  end
end
