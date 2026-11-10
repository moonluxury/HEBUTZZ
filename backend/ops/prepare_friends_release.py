"""Prepare only the friend-request changes on top of an exact server snapshot."""
import argparse
import ast
import hashlib
import json
from pathlib import Path
import shutil

FILES = ['domain.py', 'friend_note.py', 'requirements.txt', 'requirements.lock',
         'tests/test_backend.py', 'tests/test_friend_note.py']


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def replace_once(value, before, after):
    if value.count(before) != 1:
        raise RuntimeError('Server baseline changed; review this patch before deploying')
    return value.replace(before, after, 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--regression-source', type=Path)
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1]
    regression = args.regression_source or source
    base, dest = args.baseline, args.destination
    shutil.copytree(base, dest)
    domain = (base / 'domain.py').read_text(encoding='utf-8')
    domain = replace_once(domain, 'from psycopg.types.json import Jsonb\n',
                          'from psycopg.types.json import Jsonb\nfrom friend_note import valid_note\n')
    domain = replace_once(domain, "        note = string(p.get('note', ''), 120)",
                          "        note = p.get('note', '')\n"
                          "        require(valid_note(note), 'invalid_note', '申请附言最多 100 个字符。')")
    domain = replace_once(domain, "            return {'message': '你们已经是好友。'}",
                          "            return {'state': 'friend', 'message': '你们已经是好友。'}")
    (dest / 'domain.py').write_text(domain, encoding='utf-8', newline='\n')
    for filename, dependency in [('requirements.txt', 'regex>=2024.11.6'),
                                  ('requirements.lock', 'regex==2026.9.29')]:
        content = (base / filename).read_text(encoding='utf-8')
        if any(line.lower().startswith('regex') for line in content.splitlines()):
            raise RuntimeError('Existing regex dependency needs review')
        (dest / filename).write_text(content.rstrip() + '\n' + dependency + '\n', encoding='utf-8', newline='\n')
    for name in ['friend_note.py', 'tests/test_friend_note.py']:
        shutil.copy2(source / name, dest / name)
    # The local profile/ avatar tests also contain unrelated unreleased changes.
    # Append only this task's integration test to the server's existing tests.
    tests = (source / 'tests/test_backend.py').read_text(encoding='utf-8')
    selected = [node for node in ast.parse(tests).body if isinstance(node, ast.FunctionDef)
                and node.name == 'test_friend_note_visible_limit_whitespace_and_lookup_states']
    assert len(selected) == 1
    existing = (base / 'tests/test_backend.py').read_text(encoding='utf-8')
    assert selected[0].name not in existing
    (dest / 'tests/test_backend.py').write_text(existing.rstrip() + '\n\n\n' + ast.get_source_segment(tests, selected[0]) + '\n', encoding='utf-8', newline='\n')
    # Exercise the other deployed modules too, without activating changes to them.
    for module, test in [('comment_service.py', 'test_comments.py'),
                         ('submission_service.py', 'test_submissions.py')]:
        assert digest(base / module) == digest(regression / module), 'Regression tests require the same deployed implementation'
        shutil.copy2(regression / 'tests' / test, dest / 'tests' / test)
    (dest / 'ops').mkdir(exist_ok=True)
    for name in ['activate_friends_release.py', 'smoke_friends_release.py', 'friends_smoke_cleanup.py']:
        shutil.copy2(source / 'ops' / name, dest / 'ops' / name)
    manifest = {
        'files': {name: digest(dest / name) for name in FILES},
        'baseline_sha256': {name: digest(base / name) for name in FILES},
        'guard_sha256': {p.relative_to(base).as_posix(): digest(p) for p in base.rglob('*')
                         if p.is_file() and p.relative_to(base).as_posix() not in FILES},
        'candidate_sha256': {p.relative_to(dest).as_posix(): digest(p) for p in dest.rglob('*') if p.is_file()},
        'regex': '2026.9.29',
    }
    (dest / 'friends-release.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(json.dumps({'candidate': str(dest), 'files': FILES}))


if __name__ == '__main__':
    main()
