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
    @db = Analysand::Database.new(db_uri)
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
    InternetArchive.run_check(nil, Celluloid.logger)
  end
end
