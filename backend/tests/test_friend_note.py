from friend_note import valid_note


def test_visible_characters_and_preserved_whitespace():
    for text in ['', '  你好\n同学  ', '你' * 100, 'e\u0301' * 100,
                 '👩🏽‍💻' * 100, '👨‍👩‍👧‍👦' * 100, '🇨🇳' * 100]:
        assert valid_note(text)
    for text in ['你' * 101, 'e\u0301' * 101, '👩🏽‍💻' * 101, '🇨🇳' * 101,
                 '\x00', '\ud800', None, 42, 'a' + '\u0301' * 10001]:
        assert not valid_note(text)
