local www_to_bare_p = function(url_a, url_b)
  local bare_domain = string.match(url_a.host, '^www.([^.]+.[^.]+)$')

  return url_b.host == bare_domain
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  -- Is the parent a www.example.com and the child an example.com?
  local p_to_bare = www_to_bare_p(parent, urlpos.url)

  -- Is the parent an example.com and the child a www.example.com?
  local bare_to_p = www_to_bare_p(urlpos.url, parent)

  -- If either are true and the target won't be downloaded because of
  -- span-hosts rules, override the verdict.
  --
  -- Bare domains aren't supposed to resolve to anything, but these days they
  -- are very commonly an alias for www (actually, these days, you could look
  -- at it the other way around), and we assume that any site that pulls that
  -- shit is doing the bare domain thing.
  if (p_to_bare or bare_to_p) and reason == 'DIFFERENT_HOST' then
    return true
  end

  -- Is this a URL of a non-hyperlinked page requisite?
  local is_html_link = urlpos['link_expect_html']
  local is_requisite = urlpos['link_inline_p']

  if is_html_link ~= 1 and is_requisite == 1 then
    -- Did wget decide to not download it due to domain restrictions?
    if verdict == false and reason == 'DOMAIN_NOT_ACCEPTED' then
      -- Nope, you're downloading it after all.
      return true
    end
  end

  -- Return the original verdict.
  return verdict
end

-- vim:ts=2:sw=2:et:tw=78
