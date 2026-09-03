require 'analysand'
require 'celluloid'
require 'listen'

# Watches a directory containing CouchDB documents for changes and installs
# said changes.
class CouchdbDocUpdater
  include Celluloid
  include Celluloid::Logger

  def parse_credentials(creds)
    if creds
      u, p = creds.split(':', 2)

      { :username => u, :password => p }
    end
  end

  def initialize(path, uri, credentials)
    @db = Analysand::Database.new(uri)
    @credentials = parse_credentials(credentials)
    @path = path

    Dir.foreach(@path) do |filename|
      next if filename == '.' or filename == '..'
      next if not filename.end_with? '.json'
      add_set("#{@path}/#{filename}")
    end
    start_listener
  end

  def stop
    @listener.stop
  end

  def id_from_path(path)
    raise '#id_from_path must be implemented'
  end

  def start_listener
    @listener = Listen.to(@path) do |modified, added, removed|
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
