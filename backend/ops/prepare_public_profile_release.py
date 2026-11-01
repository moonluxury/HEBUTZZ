"""Patch the published profile lookup onto a fresh, exact production snapshot."""
import argparse
import ast
import hashlib
import json
from pathlib import Path
import shutil


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def once(text, before, after):
    if text.count(before) != 1:
        raise RuntimeError('Production baseline changed; review the profile patch')
    return text.replace(before, after, 1)


def function(source, name):
    found = [n for n in ast.parse(source).body if isinstance(n, ast.FunctionDef) and n.name == name]
    assert len(found) == 1
    return ast.get_source_segment(source, found[0])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1]
    manifest = json.loads(args.manifest.read_text())
    for name, value in manifest['baseline_sha256'].items():
        assert digest(args.baseline / name) == value, name
    shutil.copytree(args.baseline, args.destination)
    domain = (args.baseline / 'domain.py').read_text(encoding='utf-8')
    published = (source / 'domain.py').read_text(encoding='utf-8')
    assert 'PUBLIC_PROFILE_FIELDS' not in domain
    declaration = "FIELDS = {'display_name': 40, 'school': 80, 'college': 80, 'major': 80, 'grade': 30, 'bio': 300}"
    domain = once(domain, declaration, declaration + "\nPUBLIC_PROFILE_FIELDS = ('school', 'college', 'major', 'grade', 'bio')")
    domain = once(domain, function(domain, 'public_user'), function(published, 'public_user'))
    domain = once(domain, "return {'state': state, 'user': public_user(conn, actor, peer)}",
                  "return {'state': state, 'user': public_user(conn, actor, peer, include_profile=True)}")
    ast.parse(domain)
    (args.destination / 'domain.py').write_text(domain, encoding='utf-8', newline='\n')
    tests = (source / 'tests/test_backend.py').read_text(encoding='utf-8')
    existing = (args.baseline / 'tests/test_backend.py').read_text(encoding='utf-8')
    selected = [n.name for n in ast.parse(tests).body if isinstance(n, ast.FunctionDef) and n.name.startswith('test_public_profile_')]
    assert len(selected) == 3 and not any(name in existing for name in selected)
    existing += '\n\n' + '\n\n\n'.join(function(tests, name) for name in selected) + '\n'
    (args.destination / 'tests/test_backend.py').write_text(existing, encoding='utf-8', newline='\n')
    (args.destination / 'ops').mkdir()
    for name in ['validate_public_profile_release.py', 'activate_public_profile_release.py',
                 'smoke_public_profile_release.py', 'public_profile_smoke_cleanup.py']:
        shutil.copy2(source / 'ops' / name, args.destination / 'ops' / name)
    # Only domain.py is installed into the running application. Everything else
    # in the candidate supports isolation, testing, or rollback verification.
    manifest.update(files={'domain.py': digest(args.destination / 'domain.py')},
                    candidate_sha256={p.relative_to(args.destination).as_posix(): digest(p)
                                      for p in args.destination.rglob('*') if p.is_file()})
    (args.destination / 'public-profile-release.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(json.dumps({'candidate': str(args.destination), 'install': ['domain.py'], 'new_tests': selected}))


if __name__ == '__main__':
    main()
