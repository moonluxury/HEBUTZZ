"""Friend-request notes preserve whitespace and count Unicode grapheme clusters."""
import regex


def valid_note(value):
    # Bound work as well as displayed length; no NUL/unpaired surrogate enters PostgreSQL.
    return (isinstance(value, str) and len(value) <= 10000
            and '\x00' not in value
            and not any(0xD800 <= ord(char) <= 0xDFFF for char in value)
            and len(regex.findall(r'\X', value)) <= 100)
