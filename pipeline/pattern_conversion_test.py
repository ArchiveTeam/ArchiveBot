import re
import unittest

from pattern_conversion import lua_pattern_to_regex


class Test(unittest.TestCase):
    def test_alpha(self):
        self.assertTrue(re.search(lua_pattern_to_regex('%a'), 'a'))
        self.assertTrue(re.search(lua_pattern_to_regex('%a'), 'Z'))
        self.assertFalse(re.search(lua_pattern_to_regex('%a'), '0'))

    def test_control(self):
        self.assertTrue(re.search(lua_pattern_to_regex('%c'), '\x01'))
        self.assertFalse(re.search(lua_pattern_to_regex('%c'), 'a'))

    def test_graphic(self):
        self.assertTrue(re.search(lua_pattern_to_regex('%g'), 'P'))
        self.assertFalse(re.search(lua_pattern_to_regex('%g'), '\t'))

    def test_lowercase(self):
        self.assertTrue(re.search(lua_pattern_to_regex('%l'), 'h'))
        self.assertFalse(re.search(lua_pattern_to_regex('%l'), 'H'))

    def test_printable(self):
        self.assertTrue(re.search(lua_pattern_to_regex('%p'), ']'))
        self.assertTrue(re.search(lua_pattern_to_regex('%p'), '-'))
        self.assertTrue(re.search(lua_pattern_to_regex('%p'), '#'))
        self.assertFalse(re.search(lua_pattern_to_regex('%p'), '\x01'))

    def test_space(self):
        self.assertTrue(re.search(lua_pattern_to_regex('%s'), ' '))
        self.assertTrue(re.search(lua_pattern_to_regex('%s'), '\t'))
        self.assertFalse(re.search(lua_pattern_to_regex('%s'), 'A'))

    def test_upper(self):
        self.assertTrue(re.search(lua_pattern_to_regex('%u'), 'A'))
        self.assertFalse(re.search(lua_pattern_to_regex('%u'), 'a'))

    def test_alphanum(self):
        self.assertTrue(re.search(lua_pattern_to_regex('%w'), 'A'))
        self.assertFalse(re.search(lua_pattern_to_regex('%w'), '#'))

    def test_hex(self):
        self.assertTrue(re.search(lua_pattern_to_regex('%x'), 'A'))
        self.assertFalse(re.search(lua_pattern_to_regex('%x'), 'z'))

    def test_complex(self):
        self.assertTrue(re.search(
            lua_pattern_to_regex(r'^http://www%.reddit%.com/login%?dest='),
            'http://www.reddit.com/login?dest=archiveteam'
        ))
        self.assertFalse(re.search(
            lua_pattern_to_regex(r'^http://www%.reddit%.com/login%?dest='),
            'http://www.reddit.com/r/archiveteam'
        ))
        self.assertTrue(re.search(
            lua_pattern_to_regex(r'subscription%.php%?'),
            'subscription.php?'
        ))
        self.assertFalse(re.search(
            lua_pattern_to_regex(r'subscription%.php%?'),
            'subscriptionXphp?'
        ))
        self.assertTrue(re.search(
            lua_pattern_to_regex(r'^http://.+%.blogspot%.com/search%?'),
            'http://archiveteam.blogspot.com/search?q=archives'
        ))
        self.assertFalse(re.search(
            lua_pattern_to_regex(r'^http://.+%.blogspot%.com/search%?'),
            'http://.blogspot.com/search?q=archives'
        ))

    def test_dash(self):
        self.assertTrue(re.search(
            lua_pattern_to_regex('cat%-dog'),
            'cat-dog'
        ))
        self.assertFalse(re.search(
            lua_pattern_to_regex('cat%-dog'),
            'cattdog'
        ))
        self.assertTrue(re.search(
            lua_pattern_to_regex('cat-dog'),
            'cattdog'
        ))
        self.assertTrue(re.search(
            lua_pattern_to_regex('cat-dog'),
            'cattttdog'
        ))

    def test_nest(self):
        self.assertTrue(re.search(
            lua_pattern_to_regex('abc[%a]xyz'),
            'abcDxyz'
        ))
        self.assertFalse(re.search(
            lua_pattern_to_regex('abc[%a]xyz'),
            'abc xyz'
        ))
