require 'json'

module Packet
  module ClassMethods
    def json_attrs
      @json_attrs ||= []
    end

    def json_attr(*attrs)
      attrs.each do |attr|
        attr_accessor attr
        json_attrs << attr
      end
    end

    def self.extended(base)
      # This packet's type.  Typically, this is set in the constructor.
      base.json_attr :type
    end
  end

  def to_json(options = nil)
    self.class.json_attrs.each_with_object({}) do |a, h|
      h[a] = send(a)
    end.to_json
  end
end

class DownloadUpdate
  extend Packet::ClassMethods
  include Packet

  # The work item's internal ID.
  json_attr :ident

  # The work item's URL.
  json_attr :url

  # Response code counts.
  json_attr :r1xx, :r2xx, :r3xx, :r4xx, :r5xx, :runk

  # Total number of HTTP responses.
  json_attr :total

  # Bytes downloaded.
  json_attr :bytes_downloaded

  # Error count.
  json_attr :error_count

  # Associated log entries for this update.
  json_attr :entries
  
  def initialize(job, entries)
    self.type = 'download_update'

    self.ident = job.ident
    self.url = job.url
    self.error_count = job.error_count
    self.bytes_downloaded = job.bytes_downloaded
    self.total = job.total_responses

    counts = job.response_counts
    self.r1xx = counts['r1xx']
    self.r2xx = counts['r2xx']
    self.r3xx = counts['r3xx']
    self.r4xx = counts['r4xx']
    self.r5xx = counts['r5xx']
    self.runk = counts['runk']
    self.entries = entries
  end
end

class JobStatusChange
  extend Packet::ClassMethods
  include Packet

  # The work item's internal ID.
  json_attr :ident

  # Whether the job had an abort initiated.
  json_attr :aborted

  # Whether the job completed (e.g. has an archive URL).
  #
  # Note: Because an abort does not take effect immediately, it's possible for
  # both aborted and completed to be true.
  json_attr :completed

  def initialize(job)
    self.type = 'status_change'
    self.ident = job.ident
    self.aborted = job.aborted?
    self.completed = job.completed?
  end
end
