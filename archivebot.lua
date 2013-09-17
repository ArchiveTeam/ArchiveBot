wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  -- Is this a URL of a page requisite?
  local is_requisite = (urlpos['link_inline_p'] == 1)

  if is_requisite then
    -- Did wget decide to not download it due to domain restrictions?
    if verdict == false and reason == 'DOMAIN_NOT_ACCEPTED' then
      -- Nope, you're downloading it after all
      return true
    end
  end

  -- Return the original verdict
  return verdict
end

-- vim:ts=2:sw=2:et:tw=78
