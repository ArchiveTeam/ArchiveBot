require 'json'

##
# An ArchiveUrl object points to a WARC file for an ArchiveBot job run on some
# site at some time.
class ArchiveUrl
  ##
  # The URL for the job.  Required.
  #
  # This is used with queued_at to match an ArchiveUrl with a Job.
  attr_accessor :url

  ##
  # When the job was queued, as a UNIX timestamp.  Required.
  #
  # This is used with url to match an ArchiveUrl with a Job.
  attr_accessor :queued_at

  ##
  # The URL to the archive file.  Required.
  #
  # For WARCs, this should be a direct link to the WARC.
  attr_accessor :archive_url

  ##
  # The job ident.  Optional.
  #
  # A job ident identifies a *set* of jobs over time; one still needs the
  # queue time to uniquely identify a *single* job.
  #
  # Historically, this was only present in ArchiveBot-generated WARCs, which
  # made it difficult to extract -- and that's why ident is optional and url
  # is required.  Newer versions of ArchiveBot contain this information in a
  # more convenient container.
  attr_accessor :ident

  ##
  # The size of the archive, in bytes.  Optional.
  attr_accessor :file_size

  def initialize(url: nil, queued_at: nil, archive_url: nil, ident: nil, file_size: nil)
    self.url = url
    self.queued_at = queued_at
    self.archive_url = archive_url
    self.ident = ident
    self.file_size = file_size
  end

  def valid?
    self.url && self.queued_at && self.archive_url
  end

  def as_json
    {
      'url' => url,
      'queued_at' => queued_at.to_i,
      'ident' => ident,
      'file_size' => file_size.to_i,
      'archive_url' => archive_url
    }
  end

  def to_json(*)
    as_json.to_json
  end
end
