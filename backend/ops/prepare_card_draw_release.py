"""Add the card draw module onto the exact live wallet implementation."""
import argparse
import ast
import hashlib
import json
from pathlib import Path
import shutil


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def once(value, before, after):
    assert value.count(before) == 1, 'Live wallet changed; review the patch'
    return value.replace(before, after, 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1]
    manifest = json.loads(args.manifest.read_text())
    assert not (args.baseline / 'card_draw_service.py').exists()
    for name, value in manifest['baseline_sha256'].items(): assert digest(args.baseline / name) == value, name
    shutil.copytree(args.baseline, args.destination)
    wallet = (args.baseline / 'wallet_service.py').read_text(encoding='utf-8')
    wallet = once(wallet, "{'balance', 'catalog', 'ledger', 'orders', 'practice_begin', 'practice_finish'}",
                  "{'balance', 'catalog', 'ledger', 'orders', 'practice_begin', 'practice_finish', 'card_draw_options', 'card_draw', 'card_draw_status'}")
    wallet = once(wallet, "    if action == 'balance': result = balance(conn, actor)",
                  "    if action in {'card_draw_options', 'card_draw', 'card_draw_status'}:\n"
                  "        from card_draw_service import handle as card_draw\n"
                  "        result = card_draw(conn, actor, action, payload)\n"
                  "    elif action == 'balance': result = balance(conn, actor)")
    ast.parse(wallet)
    (args.destination / 'wallet_service.py').write_text(wallet, encoding='utf-8', newline='\n')
    for name in ['card_draw_service.py', 'tests/test_card_draws.py']:
        shutil.copy2(source / name, args.destination / name)
    (args.destination / 'ops').mkdir()
    for name in ['validate_card_draw_release.py', 'activate_card_draw_release.py', 'smoke_card_draw_release.py', 'card_draw_smoke_accounts.py']:
        shutil.copy2(source / 'ops' / name, args.destination / 'ops' / name)
    manifest['baseline_sha256']['card_draw_service.py'] = None
    manifest['files'] = {name: digest(args.destination / name) for name in ['wallet_service.py', 'card_draw_service.py']}
    manifest['candidate_sha256'] = {p.relative_to(args.destination).as_posix(): digest(p) for p in args.destination.rglob('*') if p.is_file()}
    (args.destination / 'card-draw-release.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(json.dumps({'candidate': str(args.destination), 'files': list(manifest['files'])}))


if __name__ == '__main__':
    main()
