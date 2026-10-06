import unittest
import re

from .ignoracle import Ignoracle, parameterize_record_info
from wpull.pipeline.item import URLRecord

p1 = 'www\.example\.com/foo\.css\?'
p2 = 'bar/.+/baz'

def urlrec(url, level=0):
    r = URLRecord()
    r.url = url
    r.level = level

    return r

class TestIgnoracle(unittest.TestCase):
    def setUp(self):
        self.oracle = Ignoracle()

        self.oracle.set_patterns([p1, p2])

    def test_ignores_returns_responsible_pattern(self):
        r1 = urlrec('http://www.example.com/foo.css?body=1')
        r2 = urlrec('http://www.example.com/bar/abc/def/baz')

        self.assertEqual(self.oracle.ignores(r1), p1)
        self.assertEqual(self.oracle.ignores(r2), p2)

    def test_ignores_skips_invalid_patterns(self):
        self.oracle.set_patterns(['???', p2])

        self.assertEqual(self.oracle.ignores(urlrec('http://www.example.com/bar/abc/def/baz')), p2)

    def test_ignores_supports_netloc_parameterization(self):
        pattern = '{primary_netloc}/foo\.css\?'
        self.oracle.set_patterns([pattern])

        result = self.oracle.ignores(urlrec('http://www.example.com/foo.css?body=1'))

        self.assertEqual(result, pattern)

    def test_permits_empty_brace_pairs(self):
        pattern = '{primary_netloc}{}/foo\.css\?{}'
        self.oracle.set_patterns([pattern])

        result = self.oracle.ignores(urlrec('http://www.example.com{}/foo.css?{}body=1'))

        self.assertEqual(result, pattern)

    def test_permits_empty_brace_pairs_and_regex_repetitions(self):
        pattern = '{primary_netloc}{1}/foo\.css\?{}'
        self.oracle.set_patterns([pattern])

        result = self.oracle.ignores(urlrec('http://www.example.com/foo.css?{}body=1'))

        self.assertEqual(result, pattern)

    def test_parameterization_skips_regex_ranges(self):
        pattern = '/(.*)/(\\1/){3,}'
        self.oracle.set_patterns([pattern])

        result = self.oracle.ignores(urlrec('http://www.example.com/foo/foo/foo/foo/foo'))

        self.assertEqual(result, pattern)

    def test_parameterization_skips_pattern_with_unknown_parameter(self):
        wrong = '/(.*)/(\\1/){boom}'
        right = '/(.*)/(\\1/){3,}'

        self.oracle.set_patterns([wrong, right])

        result = self.oracle.ignores(urlrec('http://www.example.com/foo/foo/foo/foo/foo'))

        self.assertEqual(result, right)

    def test_ignores_supports_url_parameterization(self):
        pattern = '{primary_url}foo\.css\?'
        self.oracle.set_patterns([pattern])

        result = self.oracle.ignores(urlrec('http://www.example.com/foo.css?body=1'))

        self.assertEqual(result, pattern)

    def test_ignores_escapes_primary_url(self):
        pattern = '{primary_url}/bar\.css\?'
        self.oracle.set_patterns([pattern])

        r = URLRecord()
        r.parent_url = 'http://www.example.com'
        r.url = 'http://www.example.com/bar.css??'
        r.level = 1

        # The ignore pattern we're using expands to
        # http://www.example.com/bar\.css\?
        # We want to make sure it'll match the double-? without trying to interpret
        # ? as a metacharacter.
        result = self.oracle.ignores(r)

        self.assertEqual(result, pattern)

    def test_ignores_with_parameterized_url_replaces_none_placeholder_with_empty_string(self):
        pattern = '{primary_url}foo\.css\?'
        self.oracle.set_patterns([pattern])

        # This should treat the pattern as if it were "foo\.css\?"
        result = self.oracle.ignores(urlrec('http://www.example.com/foo.css?body=1'))

        self.assertEqual(result, pattern)

    def test_ignores_returns_false_for_unsuccessful_match(self):
        self.assertFalse(self.oracle.ignores(urlrec('http://www.example.com/media/qux.jpg')))

    def test_set_patterns_converts_bytes_to_utf8(self):
        self.oracle.set_patterns([b'foobar'])

        self.assertEqual(self.oracle.patterns[0], 'foobar')


class TestRecordInfoParameterization(unittest.TestCase):
    def test_uses_url_for_level_zero_url(self):
        record = URLRecord()
        record.url = 'http://www.example.com/'
        record.level = 0

        result = parameterize_record_info(record)

        self.assertEqual('http://www.example.com/', result['primary_url'])
        self.assertEqual('www.example.com', result['primary_netloc'])

    def test_uses_parent_url_for_higher_level_urls(self):
        record = URLRecord()
        record.parent_url = 'http://www.example.com/'
        record.url = 'http://www.example.com/foobar'
        record.level = 1

        result = parameterize_record_info(record)

        self.assertEqual('http://www.example.com/', result['primary_url'])
        self.assertEqual('www.example.com', result['primary_netloc'])


    def test_missing_primary_url_results_in_no_netloc(self):
        result = parameterize_record_info(URLRecord())

        self.assertIsNone(result['primary_url'])
        self.assertIsNone(result['primary_netloc'])

    def test_includes_auth_and_port_in_primary_netloc(self):
        record = URLRecord()
        record.url = 'http://foo:bar@www.example.com:8080/'
        record.level = 0

        result = parameterize_record_info(record)

        self.assertEqual('foo:bar@www.example.com:8080', result['primary_netloc'])
