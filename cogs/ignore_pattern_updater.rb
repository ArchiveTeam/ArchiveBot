require 'analysand'
require 'celluloid'
require 'listen'

require File.expand_path('../ignore_pattern_id_generation', __FILE__)

# Watches the ignore patterns directory and installs new ignore pattern sets as
# they're updated.
class IgnorePatternUpdater
  include Celluloid
  include Celluloid::Logger
  include IgnorePatternIdGeneration

  def initialize(path, uri, credentials)
    @db = Analysand::Database.new(uri)
    @credentials = credentials
    @path = path

    start_listener
  end

  def stop
    @listener.stop
  end

  private

  def start_listener
    @listener = Listen.to(@path, :debug => true) do |modified, added, removed|
      removed.each { |path| delete_set(path) }
      added.each { |path| add_set(path) }
      modified.each { |path| add_set(path) }
    end

    @listener.only /\.json$/
    @listener.start
  end

  def add_set(path)
    doc_id = id_from_path(path)
    doc = JSON.parse(File.read(path))

    resp = @db.head(doc_id, @credentials)
    rev = resp.etag if resp.success?
    doc['_rev'] = rev if rev

    resp = @db.put(doc_id, doc, @credentials)
    info "PUT #{@db.uri}#{doc_id} #{resp.code}"
  end

  def delete_set(path)
    doc_id = id_from_path(path)

    resp = @db.head(doc_id, @credentials)
    rev = resp.etag if resp.success?

    @db.delete(doc_id, rev, @credentials)
    info "DELETE #{@db.uri}#{doc_id} #{resp.code}"
  end
end
