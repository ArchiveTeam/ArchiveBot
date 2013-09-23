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

  # Associated log entries for this update.
  json_attr :entries

  def initialize(job, entries)
    self.ident = job.ident
    self.url = job.url

    counts = job.response_counts
    self.r1xx = counts['1xx']
    self.r2xx = counts['2xx']
    self.r3xx = counts['3xx']
    self.r4xx = counts['4xx']
    self.r5xx = counts['5xx']
    self.runk = counts['unknown']
    self.entries = entries
  end

  def to_json(options = nil)
    self.class.json_attrs.each_with_object({}) do |a, h|
      h[a] = send(a)
    end.to_json
  end
end
