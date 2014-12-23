import unittest
import re

from .ignoracle import Ignoracle

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

    def test_ignores_supports_host_parameterization(self):
        pattern = '{primary_host}/foo\.css\?'
        self.oracle.set_patterns([pattern])

        result = self.oracle.ignores('http://www.example.com/foo.css?body=1', primary_host='www.example.com')

        self.assertEqual(result, pattern)

    def test_ignores_supports_url_parameterization(self):
        pattern = '{primary_url}foo\.css\?'
        self.oracle.set_patterns([pattern])

        result = self.oracle.ignores('http://www.example.com/foo.css?body=1', primary_url='http://www.example.com/')

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
