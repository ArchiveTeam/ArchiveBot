require 'analysand'
require 'uri'

class Couchdb
  def initialize(uri, credentials)
    @db = Analysand::Database.new(uri)
    @credentials = parse_credentials(credentials)
  end

  def record_job(job)
    begin
      doc_id ="#{job.ident}:#{job.queued_at.to_i}"
      put!(doc_id, job)
    rescue Analysand::DocumentNotSaved => e
      # A conflict indicates that doc_id already exists.  The ident is unique
      # with high probability, so this situation is a very strong indication
      # that we just received a duplicate message.  As such, we ignore
      # conflicts.
      #
      # However, other issues are treated as fatal.
      if !e.response.conflict?
        throw e
      end
    end
  end

  def put!(id, object)
    @db.put!(id, object, @credentials)
  end

  def history(url)
    params = {
      :descending => true,
      :include_docs => true,
      :key => url
    }.reject { |_,v| v.nil? }

    resp = @db.view!('jobs/history', params, @credentials)

    # Group by ident and queue time.
    grouped = resp.docs.group_by { |d| [d['ident'], d['queued_at'].to_i] }.values

    # The stupid man's outer join.
    grouped.map do |gs|
      gs.each_with_object({'archive_urls' => []}) do |d, h|
        if d['type'] == 'archive_url'
          h['archive_urls'] << d
        else
          h.update(d)
        end
      end
    end
  end

  def latest_job_record(url)
    history(url).first
  end

  def attempts_on_children(url)
    params = {
      :reduce => true,
      :startkey => [url, 0],
      :endkey => endkey(url, true)
    }

    resp = @db.view!('jobs/by_url_and_queue_time', params, @credentials)

    if resp.rows.length > 0
      resp.rows.first['value'].first
    else
      0
    end
  end

  def resolve_ignore_sets(names)
    resp = @db.view!('ignore_patterns/by_name', { keys: names }, @credentials)

    resp.rows.map { |r| [r['key'], r['value']] }
  end

  def archive_urls(ident)
    resp = @db.view!('archive_urls/by_ident', { key: ident }, @credentials)

    resp.rows.map { |r| r['value'] }
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
