require 'analysand'
require 'uri'

require File.expand_path('../history_db', __FILE__)
require File.expand_path('../job', __FILE__)
require File.expand_path('../log_update_listener', __FILE__)

class JobRecorder < LogUpdateListener
  def initialize(redis_url, update_channel, db_url, db_credentials)
    @db = HistoryDb.new(URI(db_url), db_credentials)

    super
  end

  def on_receive(ident)
    job = ::Job.from_ident(ident, uredis)

    return unless job

    if job.aborted? || job.completed?
      doc_id = "#{job.ident}:#{job.queued_at.to_i}"

      begin
        @db.put!(doc_id, job)
      rescue Analysand::DocumentNotSaved => e
        if e.response.conflict?
          warn "Document #{doc_id} already exists"
        else
          throw e
        end
      end
    end
  end
end
