'''Lua patterns to Python regular expression conversion.'''
import functools
import re


LUA_CLASS_MAP = {
'a': r'a-zA-Z',
'c': r''.join([chr(i) for i in range(0, 0x1f + 1)]) + r'\x7f',
'd': r'0-9',
'g': r'!-/0-9:-@A-Z[-`a-z{-~',
'l': r'a-z',
'p': r' !-/0-9:-@A-Z[-`a-z{-~',
's': r' \t\n\r\f\v',
'u': r'A-Z',
'w': r'a-zA-Z0-9',
'x': r'0-9a-fA-Z',
'z': r'\x00',
}


def replace_initial_pass(match):
    '''Convert Lua ``-`` to ``*?`` and use placeholder classes.'''
    text = match.group(0)

    if text[0] == '%':
        if text[1] in LUA_CLASS_MAP:
            return r'\{0}'.format(text[1].upper())
        else:
            return r'\{0}'.format(text[1])
    elif text == '-':
        return '*?'
    else:
        raise Exception('Unknown Lua match.')


def replace_class_escape(match, bracket=False):
    '''Replace our placeholder classes with the actual characters.'''
    text = match.group(0)
    assert text[0] == '\\'
    class_name = text[1].lower()

    if class_name in LUA_CLASS_MAP:
        if bracket:
            return r'[{0}]'.format(LUA_CLASS_MAP[class_name])
        else:
            return LUA_CLASS_MAP[class_name]
    else:
        return text


def replace_all_class_escapes(match):
    '''Replace all placeholder classes.'''
    text = match.group(0)
    return re.sub(r'\\.', replace_class_escape, text)


def lua_pattern_to_regex(pattern_string):
    '''Convert a Lua pattern to a regular expression.'''
    result = re.sub(r'%.|-', replace_initial_pass, pattern_string)
    result = re.sub(r'\[(.*?[^\\])\]', replace_all_class_escapes, result)
    result = re.sub(
        r'\\.', functools.partial(replace_class_escape, bracket=True), result)
    return result


if __name__ == '__main__':
    while True:
        try:
            try:
                line = raw_input()
            except NameError:
                line = input()
        except EOFError:
            break

        print(lua_pattern_to_regex(line))
