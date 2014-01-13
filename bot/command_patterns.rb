module CommandPatterns
  AC = %r{([^\s]+)(?:\s+(.+))?}
  IDENT = %r{[0-9a-z]+}
  DELAY_SPEC = %r{[\d\.]+}

  ARCHIVE           = %r{\A(?:\!a|\!archive) #{AC}\Z}
  ARCHIVEONLY       = %r{\A(?:\!ao|\!archiveonly) #{AC}\Z}
  SET_DELAY         = %r{\A\!d(?:elay)?\s+(#{IDENT})\s+(#{DELAY_SPEC})\s+(#{DELAY_SPEC})}
  SET_PAGEREQ_DELAY = %r{\A\!reqd(?:elay)?\s+(#{IDENT})\s+(#{DELAY_SPEC})\s+(#{DELAY_SPEC})}
end
