import re
import sys

from urllib.parse import urlparse

class Ignoracle(object):
    '''
    An Ignoracle tests a URL against a list of patterns and returns whether or
    not that URL should be grabbed.

    An Ignoracle's pattern list starts as the empty list.
    '''

    patterns = []

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

    def ignores(self, url, **kwargs):
        '''
        If an ignore pattern matches the given URL, returns that pattern as a string.
        Otherwise, returns False.
        '''

        pu = re.escape(kwargs.get('primary_url') or '')
        ph = re.escape(kwargs.get('primary_netloc') or '')

        for pattern in self.patterns:
            try:
                match = re.search(pattern.format(primary_url=pu, primary_netloc=ph), url)

                if match:
                    return pattern
            except re.error as error:
                print('Pattern %s is invalid (error: %s).  Ignored.' % (pattern, str(error)), file=sys.stderr)

        return False

def parameterize_url_info(url_info):
    '''
    Given a wpull url_info dict, generates a dict with primary_url and
    primary_netloc keys.  This is meant to be used in Ignoracle.ignores.

    The primary_url key is:

    1. url_info['top_url'], or
    2. url_info['url'] if url_info['level'] is zero, or
    3. None otherwise.

    If primary_url is a valid URL, the primary_netloc key is the network
    location component of primary_url (i.e. for HTTP,
    [user:password@]host[:port]).  Otherwise, primary_netloc is None.
    '''

    primary_url = None
    primary_netloc = None

    if url_info.get('level') == 0:
        primary_url = url_info.get('url')
    else:
        primary_url = url_info.get('top_url')

    if primary_url:
        parsed = urlparse(primary_url)
        primary_netloc = parsed.netloc

    return dict(
        primary_url=primary_url,
        primary_netloc=primary_netloc
    )
