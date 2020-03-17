class Ignores < Webmachine::Resource
  class << self
    attr_accessor :redis
  end

  def content_types_provided
    [
      ['text/plain', :to_text]
    ]
  end

  def to_text
    buffer = []

    return 400 if request.query['compact'] == 'true' && keys.length > 1

    keys.each do |key|
      self.class.redis.sscan_each("#{key}_ignores", count: 100) do |ignore|
        buffer << [key, ignore]
      end
    end

    if request.query['compact'] == 'true'
      # Read all ignore patterns
      #TODO: Use CouchDB instead, somehow?
      ignore_patterns_path = File.expand_path('../../../db/ignore_patterns', __FILE__)
      igsets = Hash.new
      Dir.foreach(ignore_patterns_path) do |filename|
        next if filename == '.' or filename == '..'
        next if not filename.end_with? '.json'
        setname = filename[0..-6]
        j = JSON.parse(File.read("#{ignore_patterns_path}/#{filename}"))
        next if j['type'] != 'ignore_patterns'
        igsets[setname] = j['patterns']
      end

      job_patterns = buffer.map { |key, ignore| ignore }

      # Always process global igset first
      igset_names = ['global'] + (igsets.keys - ['global'])

      # Magic (note: modifies igsets)
      job_sets = Hash.new
      orig_global_igset = igsets['global'].dup
      manual_job_patterns = job_patterns.dup  # Start off with all ignores, remove the ones found in igsets
      job_patterns.each do |pattern|
        igset_names.each do |igset_name|
          if igsets[igset_name].include?(pattern)
            # If the pattern is found in a non-global igset but the pattern is also contained in the global igset, ignore this hit and move on.
            # This prevents igsets from being matched due to duplicates with the global igset.
            if igset_name != 'global' && orig_global_igset.include?(pattern)
              igsets[igset_name].delete(pattern)
              next
            end

            job_sets[igset_name] = true
            igsets[igset_name].delete(pattern)
            manual_job_patterns.delete(pattern)
          end
        end
      end

      # Format output
      output = []
      output << "Ignore sets for job #{keys[0]}:"
      igset_names.each do |igset_name|
        if job_sets[igset_name]
          if not igsets[igset_name].empty?
            # Some ignores are excluded
            output << "  #{igset_name}, excluding:"
            igsets[igset_name].sort.each { |pattern| output << "    #{pattern}" }
          else
            output << "  #{igset_name}"
          end
        end
      end
      if not manual_job_patterns.empty?
        output << '' # Empty line between igsets and manual ignores; the global igset is always there, so the above loop will always produce at least one line and there's no need to check for this.
        output << "Manual ignores for job #{keys[0]}:"
        manual_job_patterns.sort.each { |pattern| output << "  #{pattern}" }
      end

      output.join("\n")
    else
      buffer.sort_by! { |p| p.reverse }.map! { |p| p.join("\t") }.join("\n")
    end
  end

  private

  def keys
    request.path_tokens.last.split(',')
  end
end
