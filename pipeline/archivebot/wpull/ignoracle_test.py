import unittest
import wpull.pipeline.item

from .ignoracle import Ignoracle, parameterize_record_info

p1 = 'www\.example\.com/foo\.css\?'
p2 = 'bar/.+/baz'

def make_url_record(url, level = 0, parent_url = None, root_url = None):
    # Without kwargs, the URL is treated as a root URL, i.e. its own parent
    # root_url defaults to parent_url if present else url
    if parent_url is None:
        parent_url = url
    if root_url is None:
        root_url = parent_url
    record = wpull.pipeline.item.URLRecord()
    record.url = url
    record.parent_url = parent_url
    record.root_url = root_url
    record.level = level
    return record

class TestIgnoracle(unittest.TestCase):
    def setUp(self):
        self.oracle = Ignoracle()

        self.oracle.set_patterns([p1, p2])

    def test_ignores_returns_responsible_pattern(self):
        self.assertEqual(self.oracle.ignores(make_url_record('http://www.example.com/foo.css?body=1')), p1)
        self.assertEqual(self.oracle.ignores(make_url_record('http://www.example.com/bar/abc/def/baz')), p2)

    def test_ignores_skips_invalid_patterns(self):
        self.oracle.set_patterns(['???', p2])

        self.assertEqual(self.oracle.ignores(make_url_record('http://www.example.com/bar/abc/def/baz')), p2)

    def test_ignores_supports_netloc_parameterization(self):
        pattern = '{primary_netloc}/foo\.css\?'
        self.oracle.set_patterns([pattern])

        result = self.oracle.ignores(make_url_record('http://www.example.com/foo.css?body=1'))

        self.assertEqual(result, pattern)

    def test_permits_empty_brace_pairs(self):
        pattern = '{primary_netloc}{}/foo\.css\?{}'
        self.oracle.set_patterns([pattern])

        record = make_url_record('http://www.example.com{}/foo.css?{}body=1', level = 1, parent_url = 'http://www.example.com/')
        result = self.oracle.ignores(record)

        self.assertEqual(result, pattern)

    def test_permits_empty_brace_pairs_and_regex_repetitions(self):
        pattern = '{primary_netloc}{1}/foo\.css\?{}'
        self.oracle.set_patterns([pattern])

        result = self.oracle.ignores(make_url_record('http://www.example.com/foo.css?{}body=1'))

        self.assertEqual(result, pattern)

    def test_parameterization_skips_regex_ranges(self):
        pattern = '/(.*)/(\\1/){3,}'
        self.oracle.set_patterns([pattern])

        result = self.oracle.ignores(make_url_record('http://www.example.com/foo/foo/foo/foo/foo'))

        self.assertEqual(result, pattern)

    def test_parameterization_skips_pattern_with_unknown_parameter(self):
        wrong = '/(.*)/(\\1/){boom}'
        right = '/(.*)/(\\1/){3,}'

        self.oracle.set_patterns([wrong, right])

        result = self.oracle.ignores(make_url_record('http://www.example.com/foo/foo/foo/foo/foo'))

        self.assertEqual(result, right)

    def test_ignores_supports_url_parameterization(self):
        pattern = '{primary_url}foo\.css\?'
        self.oracle.set_patterns([pattern])

        record = make_url_record('http://www.example.com/foo.css?body=1', level = 1, parent_url = 'http://www.example.com/')
        result = self.oracle.ignores(record)

        self.assertEqual(result, pattern)

    def test_ignores_escapes_url(self):
        pattern = '{primary_url}foo\.css\?'
        self.oracle.set_patterns([pattern])

        record = make_url_record('http://www.example.com/bar.css??/foo.css?body=1', level = 1, parent_url = 'http://www.example.com/bar.css??/')
        result = self.oracle.ignores(record)

        self.assertEqual(result, pattern)

    def test_ignores_with_parameterized_url_replaces_none_placeholder_with_empty_string(self):
        pattern = '{primary_url}foo\.css\?'
        self.oracle.set_patterns([pattern])

        # This should treat the pattern as if it were "foo\.css\?"
        record = wpull.pipeline.item.URLRecord()
        record.url = 'http://www.example.com/foo.css?body=1'
        record.level = 1
        # No parent or root URL...
        result = self.oracle.ignores(record)

        self.assertEqual(result, pattern)

    def test_ignores_returns_false_for_unsuccessful_match(self):
        self.assertFalse(self.oracle.ignores(make_url_record('http://www.example.com/media/qux.jpg')))

    def test_set_patterns_converts_bytes_to_utf8(self):
        self.oracle.set_patterns([b'foobar'])

        self.assertEqual(self.oracle.patterns[0], 'foobar')

class TestRecordInfoParameterization(unittest.TestCase):
    def test_uses_root_url(self):
        record = make_url_record('http://www.example.com/foo', level = 1, parent_url = 'http://www.example.com/', root_url = 'https://example.org/')

        result = parameterize_record_info(record)

        self.assertEqual('https://example.org/', result['primary_url'])
        self.assertEqual('example.org', result['primary_netloc'])

    def test_uses_url_for_level_zero_url(self):
        record = make_url_record('http://www.example.com/', level = 0, parent_url = 'http://parent.invalid/', root_url = 'http://root.invalid/')

        result = parameterize_record_info(record)

        self.assertEqual('http://www.example.com/', result['primary_url'])
        self.assertEqual('www.example.com', result['primary_netloc'])

    def test_includes_auth_and_port_in_primary_netloc(self):
        record = make_url_record('http://foo:bar@www.example.com:8080/')

        result = parameterize_record_info(record)

        self.assertEqual('foo:bar@www.example.com:8080', result['primary_netloc'])

    def test_none_if_no_root_url(self):
        record = wpull.pipeline.item.URLRecord()
        record.url = 'http://www.example.com/foo.css?body=1'
        record.level = 1
        record.parent_url = 'http://www.example.com/'

        result = parameterize_record_info(record)

        self.assertIsNone(result['primary_url'])
        self.assertIsNone(result['primary_netloc'])
