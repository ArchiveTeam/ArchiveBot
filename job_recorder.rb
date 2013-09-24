require 'analysand'

require File.expand_path('../log_update_listener', __FILE__)
require File.expand_path('../job', __FILE__)

class JobRecorder < LogUpdateListener
  def initialize(redis_url, update_channel, db_url, db_credentials)
    @db = Analysand::Database.new(URI(db_url))
    @credentials = db_credentials

    super
  end

  def on_receive(ident)
    job = ::Job.from_ident(ident, uredis)

    return unless job

    if job.aborted? || job.completed?
      doc_id = "#{job.ident}:#{job.queued_at.to_i}"

      begin
        @db.put!(doc_id, job, @credentials)
      rescue Analysand::DocumentNotSaved => e
        if e.response.conflict?
          error "Conflict occurred on document #{doc_id}"
        else
          throw e
        end
      end
    end
  end
end
