require 'analysand'
require 'celluloid'

require File.expand_path('../../lib/archive_url_generators', __FILE__)

class ArchiveFinder
  include ArchiveUrlGenerators
  include Celluloid

  ##
  # Seconds between archive checks.
  INTERVAL = 3600
  
  def initialize(db_uri, db_credentials)
    @db_uri = db_uri
    @credentials = db_credentials
    @timer = every(INTERVAL) { run_check }

    async.run_check
  end

  def stop
    @timer.cancel
  end

  private

  def run_check
    async.run_ia_check
  end

  def run_ia_check
    recorder = IaRecorder.new(@db_uri, @db_credentials)

    InternetArchive.run_check(nil, Celluloid.logger, recorder)
  end
end

class IaRecorder
  def initialize(db_uri, db_credentials)
    @db = Analysand::Database.new(db_uri)
    @credentials = db_credentials
  end

  def record_archive_urls(urls)
  end

  def record_failed_pack_url(pack_url)
  end

  def set_latest_addeddate(addeddate)
  end
end
