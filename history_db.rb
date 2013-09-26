require 'analysand'
require 'uri'

class HistoryDb
  def initialize(uri, credentials)
    @db = Analysand::Database.new(uri)
    @credentials = parse_credentials(credentials)
  end

  def put!(doc_id, job)
    @db.put!(doc_id, job, @credentials)
  end

  def history_by_ident(ident, limit, start_at = nil)
    resp = @db.view!('jobs/by_ident', :key => ident)
    url = resp.rows.first['value']

    history(url, limit, start_at)
  end

  def history(url, limit, start_at = nil, prefix = false)
    normalized = URI(url).normalize.to_s

    params = {
      :include_docs => true,
      :limit => limit,
      :reduce => false,
      :descending => true,
      :endkey_docid => start_at,
      :endkey => [normalized, 0],
      :startkey => endkey(normalized, prefix)
    }.reject! { |_,v| v.nil? }

    @db.view('jobs/by_url_and_queue_time', params, @credentials)
  end

  def summary(url, limit, start_at = nil, prefix = false)
    normalized = URI(url).normalize.to_s

    params = {
      :limit => limit,
      :group => true,
      :group_level => 1,
      :descending => true,
      :endkey_docid => start_at,
      :endkey => [normalized, 0],
      :startkey => endkey(normalized, prefix)
    }.reject! { |_,v| v.nil? }

    @db.view('jobs/by_url_and_queue_time', params, @credentials)
  end

  private

  def endkey(url, prefix)
    # Look up CouchDB's view key collation order for more information
    [prefix ? "#{url}\uFFFF" : url, 'a']
  end

  def parse_credentials(creds)
    if creds
      u, p = creds.split(':', 2)

      { :username => u, :password => p }
    end
  end
end
