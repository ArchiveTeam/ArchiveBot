require File.expand_path('../couchdb_doc_updater', __FILE__)
require File.expand_path('../ignore_pattern_id_generation', __FILE__)

# Watches the ignore patterns directory and installs new ignore pattern sets as
# they're updated.
class IgnorePatternUpdater < CouchdbDocUpdater
  include IgnorePatternIdGeneration
end
