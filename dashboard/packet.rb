require 'json'

# An update packet.
class Packet
  def self.json_attrs
    @json_attrs ||= []
  end

  def self.json_attr(*attrs)
    attrs.each do |attr|
      attr_accessor attr
      json_attrs << attr
    end
  end

  # The work item's internal ID.
  json_attr :ident

  # The work item's URL.
  json_attr :url

  # Response code counts.
  json_attr :r1xx, :r2xx, :r3xx, :r4xx, :r5xx, :runk

  # The latest URL fetched from the work item, its HTTP response code, and
  # wget's interpretation of the result.
  json_attr :last_fetched_url, :last_fetched_response_code,
    :last_fetched_wget_code

  def self.from_job(job)
    new.tap do |p|
      p.ident = job.ident
      p.url = job.url

      counts = job.response_counts
      p.r1xx = counts['1xx']
      p.r2xx = counts['2xx']
      p.r3xx = counts['3xx']
      p.r4xx = counts['4xx']
      p.r5xx = counts['5xx']
      p.runk = counts['unknown']
    end
  end

  def to_json(options = nil)
    self.class.json_attrs.each_with_object({}) do |a, h|
      h[a] = send(a)
    end.to_json
  end
end
