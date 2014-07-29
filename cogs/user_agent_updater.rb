require File.expand_path('../couchdb_doc_updater', __FILE__)

# Watches the user agents directory and installs new user agent aliases as
# they're updated.
class UserAgentUpdater < CouchdbDocUpdater
  def id_from_path(path)
    basename = File.basename(path)
    doc_id = basename.sub(File.extname(path), '')

    "user_agents:#{doc_id}"
  end
end
