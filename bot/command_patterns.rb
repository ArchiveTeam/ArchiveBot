module CommandPatterns
  AC = %r{([^\s]+)(?:\s+(.+))?}
  IDENT = %r{[0-9a-z]+}
  DELAY_SPEC = %r{[\d]+}

  ARCHIVE           = %r{\A(?:\!a|\!archive|\!firstworldproblems)(?!\s+<)\s+#{AC}\s*\Z}
  ARCHIVE_FILE      = %r{\A(?:\!a|\!archive|\!firstworldproblems)\s+<\s+#{AC}\s*\Z}
  ARCHIVEONLY       = %r{\A(?:\!ao|\!archiveonly)(?!\s+<)\s+#{AC}\s*\Z}
  ARCHIVEONLY_FILE  = %r{\A(?:\!ao|\!archiveonly)\s+<\s+#{AC}\s*\Z}
  SET_DELAY         = %r{\A\!d(?:elay)?\s+(#{IDENT})\s+(#{DELAY_SPEC})\s+(#{DELAY_SPEC})}
  SET_CONCURRENCY   = %r{\A\!con(?:currency)?\s+(#{IDENT})\s+(\d+)}
  IGNORE            = %r{\A!ig(?:nore)?\s+(#{IDENT})\s+([^\s]+)\s*\Z}
  UNIGNORE          = %r{\A!unig(?:nore)?\s+(#{IDENT})\s+([^\s]+)\s*\Z}
end
