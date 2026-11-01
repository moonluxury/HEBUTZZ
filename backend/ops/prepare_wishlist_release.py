"""Apply only the wishlist change onto a fresh production snapshot."""
import argparse
import ast
import hashlib
import json
from pathlib import Path
import shutil


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def once(source, old, new):
    assert source.count(old) == 1, 'Production baseline changed; review before deploying'
    return source.replace(old, new, 1)


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
    domain = once(domain, "'send_gift', 'study_save'}", "'send_gift', 'study_save', 'wishlist_update'}")
    domain = once(domain, "'trade_action', 'report', 'send_gift'}", "'trade_action', 'report', 'send_gift', 'wishlist_update'}")
    domain = once(domain,
        "    if action == 'wishlist':\n        require_friend(conn, actor, string(p.get('peer_id'), 64, False))\n        raise DomainError('unavailable', '收藏想要目前保存在对方设备，尚未开启云端同步。', 409)",
        "    if action in {'wishlist', 'wishlist_load', 'wishlist_update'}:\n        from wishlist_service import handle as wishlist_handle\n        return wishlist_handle(conn, actor, action, p)")
    ast.parse(domain)
    (args.destination / 'domain.py').write_text(domain, encoding='utf-8', newline='\n')
    files = ['domain.py','wishlist_service.py','migrations/006_collection_wishlist.sql']
    for name in files[1:] + ['tests/test_wishlist.py']:
        assert not (args.baseline / name).exists()
        shutil.copy2(source / name, args.destination / name)
    (args.destination / 'ops').mkdir(exist_ok=True)
    for name in ['validate_wishlist_release.py','activate_wishlist_release.py','smoke_wishlist_release.py','wishlist_smoke_cleanup.py']:
        shutil.copy2(source / 'ops' / name,args.destination / 'ops' / name)
    manifest.update(files={name:digest(args.destination/name) for name in files},
                    candidate_sha256={p.relative_to(args.destination).as_posix():digest(p)
                                      for p in args.destination.rglob('*') if p.is_file()})
    (args.destination/'wishlist-release.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print(json.dumps({'candidate':str(args.destination),'install':files}))


if __name__ == '__main__': main()
