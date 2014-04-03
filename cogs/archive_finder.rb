require 'analysand'
require 'celluloid'
require 'redis'

require File.expand_path('../../lib/archive_url_generators', __FILE__)

##
# Periodically looks for and records URLs to ArchiveBot-generated archives.
#
# ArchiveFinder strategies are defined in ../../lib/archive_url_generators.
#
#
# Some words on ArchiveFinder strategies
# --------------------------------------
#
# With regard to archive URL data, ArchiveFinder strategies MUST:
#
# 1. Generate ArchiveUrl instances to represent archive URLs.
# 2. Use ArchiveBot's CouchDB instance for storing archive URL records.
# 3. Be idempotent, i.e. it MUST be possible to store the same record multiple
#    times without duplication or error.
#
# ArchiveFinder strategies MAY use said CouchDB instance for storing working
# state, but it is RECOMMENDED to use ArchiveBot's Redis instance for that, as
# continuous CouchDB database updates may unnecessarily increase CouchDB
# database indexing.
class ArchiveFinder
  include ArchiveUrlGenerators
  include Celluloid

  ##
  # Seconds between archive checks.
  INTERVAL = 3600
  
  def initialize(redis, db_uri, db_credentials)
    @redis = ::Redis.new(:url => redis)
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
    recorder = IaRecorder.new(@redis, @db_uri, @db_credentials)

    InternetArchive.run_check(recorder.latest_addeddate, Celluloid.logger, recorder)
  end
end

class IaRecorder
  KEY_PREFIX = "archive_finder:ia"
  IA_RECORDER_NAMESPACE = UUIDTools::UUID.parse('da9c866c-8fb7-45ee-809a-6df82a44a75c')

  def initialize(redis, db_uri, db_credentials)
    @redis = redis
    @db = Analysand::Database.new(db_uri)
    @credentials = db_credentials
  end

  def record_archive_urls(urls)
    records = urls.each_with_object([]) { |url, a| a << archive_url_for(url) }
    resp = @db.bulk_docs(records)

    # We accept both all success and "the only error was conflict" responses.
    resp.success? || all_conflict?(resp)
  end

  def record_failed_pack_url(pack_url)
    @redis.sadd "#{KEY_PREFIX}:failed_pack_urls", pack_url
  end

  def set_latest_addeddate(addeddate)
    @redis.set "#{KEY_PREFIX}:latest_addeddate", addeddate
  end

  def latest_addeddate
    @redis.get "#{KEY_PREFIX}:latest_addeddate"
  end

  private

  def archive_url_for(url)
    id = "#{KEY_PREFIX}:#{url.uuid.to_i.to_s(36)}"

    { '_id' => id }.merge(url.as_json)
  end

  def all_conflict?(resp)
    types = resp.body.map { |r| r['error'] }.uniq.compact

    types == ['conflict']
  end
end
