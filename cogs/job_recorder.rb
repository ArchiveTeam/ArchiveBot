require 'analysand'
require 'celluloid'

require File.expand_path('../../lib/couchdb', __FILE__)

class JobRecorder
  include Celluloid

  def initialize(db_uri, db_credentials)
    @db = Couchdb.new(db_uri, db_credentials)
  end

  def process(job)
    if job.finished?
      @db.record_job(job)
    end
  end
end
