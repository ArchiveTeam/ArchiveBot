import unittest
import re

from .ignoracle import Ignoracle, parameterize_record_info

p1 = 'www\.example\.com/foo\.css\?'
p2 = 'bar/.+/baz'

class TestIgnoracle(unittest.TestCase):
    def setUp(self):
        self.oracle = Ignoracle()

        self.oracle.set_patterns([p1, p2])

    def test_ignores_returns_responsible_pattern(self):
        self.assertEqual(self.oracle.ignores('http://www.example.com/foo.css?body=1'), p1)
        self.assertEqual(self.oracle.ignores('http://www.example.com/bar/abc/def/baz'), p2)

    def test_ignores_skips_invalid_patterns(self):
        self.oracle.set_patterns(['???', p2])

        self.assertEqual(self.oracle.ignores('http://www.example.com/bar/abc/def/baz'), p2)

    def test_ignores_supports_netloc_parameterization(self):
        pattern = '{primary_netloc}/foo\.css\?'
        self.oracle.set_patterns([pattern])

        result = self.oracle.ignores('http://www.example.com/foo.css?body=1', primary_netloc='www.example.com')

        self.assertEqual(result, pattern)

    def test_honors_empty_brace_pairs(self):
        pattern = '{primary_netloc}{}/foo\.css\?{}'
        self.oracle.set_patterns([pattern])

        result = self.oracle.ignores('http://www.example.com{}/foo.css?{}body=1', primary_netloc='www.example.com')

        self.assertEqual(result, pattern)

    def test_parameterization_skips_regex_ranges(self):
        pattern = '/(.*)/(\\1/){3,}'
        self.oracle.set_patterns([pattern])

        result = self.oracle.ignores('http://www.example.com/foo/foo/foo/foo/foo')

        self.assertEqual(result, pattern)

    def test_parameterization_skips_pattern_with_unknown_parameter(self):
        wrong = '/(.*)/(\\1/){boom}'
        right = '/(.*)/(\\1/){3,}'

        self.oracle.set_patterns([wrong, right])

        result = self.oracle.ignores('http://www.example.com/foo/foo/foo/foo/foo')

        self.assertEqual(result, right)

    def test_ignores_supports_url_parameterization(self):
        pattern = '{primary_url}foo\.css\?'
        self.oracle.set_patterns([pattern])

        result = self.oracle.ignores('http://www.example.com/foo.css?body=1', primary_url='http://www.example.com/')

        self.assertEqual(result, pattern)

    def test_ignores_escapes_url(self):
        pattern = '{primary_url}foo\.css\?'
        self.oracle.set_patterns([pattern])

        result = self.oracle.ignores('http://www.example.com/bar.css??/foo.css?body=1', primary_url='http://www.example.com/bar.css??/')

        self.assertEqual(result, pattern)

    def test_ignores_with_parameterized_url_replaces_none_placeholder_with_empty_string(self):
        pattern = '{primary_url}foo\.css\?'
        self.oracle.set_patterns([pattern])

        # This should treat the pattern as if it were "foo\.css\?"
        result = self.oracle.ignores('http://www.example.com/foo.css?body=1')

        self.assertEqual(result, pattern)

    def test_ignores_returns_false_for_unsuccessful_match(self):
        self.assertFalse(self.oracle.ignores('http://www.example.com/media/qux.jpg'))

    def test_set_patterns_converts_bytes_to_utf8(self):
        self.oracle.set_patterns([b'foobar'])

        self.assertEqual(self.oracle.patterns[0], 'foobar')

class TestRecordInfoParameterization(unittest.TestCase):
    def test_uses_top_url_if_present(self):
        record_info = dict(
            top_url='http://www.example.com/'
        )

        result = parameterize_record_info(record_info)

        self.assertEqual('http://www.example.com/', result['primary_url'])
        self.assertEqual('www.example.com', result['primary_netloc'])

    def test_uses_url_for_level_zero_url(self):
        record_info = dict(
            url='http://www.example.com/',
            level=0
        )

        result = parameterize_record_info(record_info)

        self.assertEqual('http://www.example.com/', result['primary_url'])
        self.assertEqual('www.example.com', result['primary_netloc'])

    def test_missing_primary_url_results_in_no_netloc(self):
        result = parameterize_record_info(dict())

        self.assertIsNone(result['primary_url'])
        self.assertIsNone(result['primary_netloc'])

    def test_includes_auth_and_port_in_primary_netloc(self):
        record_info = dict(
            url='http://foo:bar@www.example.com:8080/',
            level=0
        )

        result = parameterize_record_info(record_info)

        self.assertEqual('foo:bar@www.example.com:8080', result['primary_netloc'])
