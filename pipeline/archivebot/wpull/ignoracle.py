'''ignoracle: hold and check URLs against ignore patterns
'''

import re
import sys

from urllib.parse import urlparse

import wpull
import wpull.pipeline.item

def parameterize_record_info(record_info: wpull.pipeline.item.URLRecord):
    '''
    Given a wpull record_info dict, generates a dict with primary_url and
    primary_netloc keys.  This is meant to be used in Ignoracle.ignores.

    The primary_url key is generally the URL the job was started with, or a
    URL from a URL list.

    If primary_url is a valid URL, the primary_netloc key is the network
    location component of primary_url (i.e. for HTTP,
    [user:password@]host[:port]).  Otherwise, primary_netloc is None.
    '''

    primary_url = None
    primary_netloc = None

    if record_info.level == 0:
        primary_url = record_info.url
    else:
        primary_url = record_info.parent_url

    if primary_url:
        parsed = urlparse(primary_url)
        primary_netloc = parsed.netloc

    return dict(
        primary_url=primary_url,
        primary_netloc=primary_netloc
    )


'''
Workaround for {}s that might appear in ignore patterns; format interprets
these as positional parameters.
'''
pos_placeholders = ['{}'] * 256

class Ignoracle(object):
    '''
    An Ignoracle tests a URL against a list of patterns and returns whether or
    not that URL should be grabbed.

    An Ignoracle's pattern list starts as the empty list.
    '''

    patterns = []

    def __init__(self):
        self._primary = None
        self._compiled = []

    def set_patterns(self, strings):
        '''
        Given a list of strings, replaces this Ignoracle's pattern state with
        that list.
        '''

        self.patterns = []

        for string in strings:
            if isinstance(string, bytes):
                string = string.decode('utf-8')

            self.patterns.append(string)

        self._primary = None
        self._compiled = []

    def ignores(self, url_record: wpull.pipeline.item.URLRecord):
        '''
        If an ignore pattern matches the given URL, returns that pattern as a string.
        Otherwise, returns False.
        '''

        params = parameterize_record_info(url_record)

        primaryUrl = params.get('primary_url') or ''
        primaryNetloc = params.get('primary_netloc') or ''
        if self._primary != (primaryUrl, primaryNetloc):
            self._compiled = []
            escapedPrimaryUrl = re.escape(primaryUrl)
            escapedPrimaryNetloc = re.escape(primaryNetloc)
            for pattern in self.patterns:
                try:
                    expanded = pattern.replace('{primary_url}', escapedPrimaryUrl)
                    expanded = expanded.replace('{primary_netloc}', escapedPrimaryNetloc)
                    compiledPattern = re.compile(expanded)
                except re.error as error:
                    print('Pattern %s is invalid (error: %s).  Ignored.'
                          % (pattern, str(error)), file=sys.stderr)
                self._compiled.append((pattern, compiledPattern))
            self._primary = (primaryUrl, primaryNetloc)

        for pattern, compiled in self._compiled:
            match = compiled.search(url_record.url)

            if match:
                return pattern

        return False

# vim: ts=4:sw=4:et:tw=78

