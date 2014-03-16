import re

# Is this a URL of a non-hyperlinked page requisite?
def is_page_requisite(record_info):
  is_html_link = record_info['link_type']
  is_requisite = record_info['inline']

  return is_html_link != 'html' and is_requisite


# Given two URLs A and B, determines whether a link between A and B is
#
# 1. a www.DOMAIN -> DOMAIN transition or a DOMAIN -> www.DOMAIN transition
# 2. whether A's path is a subpath of B
#
# These days, bare domains are very commonly an alias for www (actually, it
# might be more correct to state that the other way around).  Therefore we
# should crawl links like
#
# http://www.example.com/foo -> http://example.com/foo/bar (it's a child)
# http://example.com/foo -> http://www.example.com/foo (same path level)
#
# but not links like
#
# http://www.example.com/foo -> http://example.com/baz (different path)
# http://example.com/bar -> http://ugh.example.com/bar (different domain)
#
# This is a rather odd heuristic, but so are bare domains.
#
# url_a and url_b must be tables containing the keys "url" and "path".  The
# url key must contain an absolute URL; the path key must contain an absolute
# path component.
def is_www_to_bare(parent, child):
  def www_to_bare_p(host_a, host_b):
    if host_a is None:
      # XXX: wpull's URLInfo uses urlsplit which may return None as hostname
      # for invalid URLs. This check is just a precaution in case an invalid
      # URL slips by into here.
      return False

    bare_domain_match = re.match(r'^www.([^.]+.[^.]+)$', host_a)

    if bare_domain_match:
      bare_domain = bare_domain_match.group(1)
      return host_b == bare_domain


  # Is the parent a www.example.com and the child an example.com, or vice
  # versa?
  p_to_bare = www_to_bare_p(parent['hostname'], child['hostname'])
  bare_to_p = www_to_bare_p(child['hostname'], parent['hostname'])

  # Is the parent's path a subpath of the child's path?
  is_subpath = parent['path'].startswith(child['path'])

  return (p_to_bare or bare_to_p) and is_subpath


def is_span_host_filter_failed_only(filter_statuses):
  for name, passed in filter_statuses.items():
    if not passed and name != 'SpanHostsFilter':
      return False

  return filter_statuses['SpanHostsFilter'] == False


# vim:ts=2:sw=2:et:tw=78
