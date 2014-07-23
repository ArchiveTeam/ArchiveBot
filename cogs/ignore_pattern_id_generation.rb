module IgnorePatternIdGeneration
  def id_from_path(path)
    basename = File.basename(path)
    doc_id = basename.sub(File.extname(path), '')

    "ignore_patterns:#{doc_id}"
  end
end
