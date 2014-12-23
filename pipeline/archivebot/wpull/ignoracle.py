import re
import sys

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

        pu = kwargs.get('primary_url') or ''
        ph = kwargs.get('primary_host') or ''

        for pattern in self.patterns:
            try:
                match = re.search(pattern.format(primary_url=pu, primary_host=ph), url)

                if match:
                    return pattern
            except re.error as error:
                print('Pattern %s is invalid (error: %s).  Ignored.' % (pattern, str(error)), file=sys.stderr)

        return False
