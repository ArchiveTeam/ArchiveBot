require 'analysand'

class LogDb
  def initialize(uri, credentials)
    @db = Analysand::Database.new(uri)
    @credentials = credentials
  end

  ##
  # Given an array of the form
  #
  #   [JSON string, numeric, ..., JSON string, numeric]
  #
  # and an amplified job, this method JSON-parses all strings, generates
  # CouchDB documents of the form
  #
  #   { "_id": (string),
  #     "score": (score),
  #     "log_data": (JSON object)
  #   }
  #
  # and then adds those documents to the database identified by the given URI.
  #
  # Raises an Analysand::BulkOperationFailed if the database write fails.
  # Raises a JSON::ParserError if any of the log strings cannot be interpreted
  # as JSON.
  def add_entries(entries, job)
    return if entries.empty?

    docs = entries.map do |entry, score|
      make_doc(entry, score, job)
    end

    @db.bulk_docs!(docs, @credentials)
  end

  private

  def make_doc(entry, score, job)
    uuid = "#{job.ident}:#{job.started_at}:#{score}"

    {
      '_id' => uuid,
      'ident' => job.ident,
      'log_entry' => JSON.parse(entry),
      'score' => score,
      'started_at' => job.started_at,
      'started_by' => job.started_by,
      'url' => job.url,
      'version' => 1
    }
  end
end
