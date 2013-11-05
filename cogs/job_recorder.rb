require 'analysand'
require 'uri'

require File.expand_path('../../lib/couchdb', __FILE__)
require File.expand_path('../../lib/job', __FILE__)
require File.expand_path('../../lib/log_update_listener', __FILE__)

class JobRecorder < LogUpdateListener
  def initialize(redis_url, update_channel, db_url, db_credentials)
    @db = Couchdb.new(URI(db_url), db_credentials)

    super
  end

  def on_receive(ident)
    job = ::Job.from_ident(ident, uredis)

    return unless job

    if job.finished?
      doc_id = "#{job.ident}:#{job.queued_at.to_i}"

      begin
        @db.put!(doc_id, job)
      rescue Analysand::DocumentNotSaved => e
        # A conflict indicates that doc_id already exists.  The ident is unique
        # with high probability, so this situation is a very strong indication
        # that we just received a duplicate message.  As such, we ignore
        # conflicts.
        #
        # However, other issues are treated as fatal.
        if !e.response.conflict?
          throw e
        end
      end
    end
  end
end
