require 'addressable/uri'
require 'json'
require 'webmachine'

require File.expand_path('../../../lib/job', __FILE__)

class Finished < Webmachine::Resource
  class << self
    attr_accessor :redis
  end

  def get_all_job_ids
    # Returns all jobs in Redis; this includes queued and currently running ones
    jobs = Set.new # Redis's SCAN may return keys multiple time, so use a set to dedupe
    # Because the main job data lies in a key of just the job ID, it's not (easily) possible to SCAN them.
    # So instead, abuse the ignore_patterns_set_key entries and extract the job ID from those.
    # (The log_key entries only exist for currently running jobs.)
    self.class.redis.scan_each(:match => "*_ignores") { |key| jobs.add(key[0..-9]) }
    jobs
  end

  def get_finished_jobs
    jobs = []
    get_all_job_ids.each do |ident|
      # Don't do this at home, kids.
      j = Job.new(nil, self.class.redis)
      j.instance_variable_set(:@ident, ident)
      h = self.class.redis.hgetall(ident)
      j.from_hash(h)
      if j && j.finished?
        j[:uri] = Addressable::URI.parse(h['url']).normalize
        jobs.push(j.as_json)
      end
    end
    jobs
  end

  def content_types_provided
    [
      ['application/json', :to_json],
      ['text/html', :to_html]
    ]
  end

  def to_json
    response.headers['Access-Control-Allow-Origin'] = '*'
    get_finished_jobs.to_json
  end

  def to_html
    File.read(File.expand_path('../../finished.html', __FILE__))
  end
end
