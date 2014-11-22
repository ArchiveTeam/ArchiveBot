module CommandPatterns
  AC = %r{([^\s]+)(?:\s+(.+))?}
  IDENT = %r{[0-9a-z]+}
  DELAY_SPEC = %r{[\d\.]+}

  ARCHIVE           = %r{\A(?:\!a|\!archive|\!firstworldproblems) #{AC}\Z}
  ARCHIVE_FILE      = %r{\A(?:\!a|\!archive|\!firstworldproblems)\s+<\s+#{AC}\Z}
  ARCHIVEONLY       = %r{\A(?:\!ao|\!archiveonly)(?!\s+<)\s+#{AC}\Z}
  ARCHIVEONLY_FILE  = %r{\A(?:\!ao|\!archiveonly)\s+<\s+#{AC}\Z}
  SET_DELAY         = %r{\A\!d(?:elay)?\s+(#{IDENT})\s+(#{DELAY_SPEC})\s+(#{DELAY_SPEC})}
  SET_CONCURRENCY   = %r{\A\!con(?:currency)?\s+(#{IDENT})\s+(\d+)}
end
