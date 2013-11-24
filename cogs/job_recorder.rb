require 'analysand'
require 'celluloid'
require 'uri'

require File.expand_path('../../lib/couchdb', __FILE__)

class JobRecorder
  include Celluloid

  def initialize(db_url, db_credentials)
    @db = Couchdb.new(URI(db_url), db_credentials)
  end

  def process(job)
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
