"""Build a comments-only release from a downloaded, verified server baseline.

No unrelated working-tree application, domain or submission changes are deployed.
The manifest pins every overwritten server file and is checked again on activation.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil


def replace_once(source, before, after):
    if source.count(before) != 1:
        raise RuntimeError('Server baseline changed; review the patch before deploying')
    return source.replace(before, after, 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    backend = Path(__file__).resolve().parents[1]
    destination = args.destination
    destination.mkdir(parents=True, exist_ok=False)
    (destination / 'migrations').mkdir()
    (destination / 'tests').mkdir()
    original = {}
    for name in ['app.py', 'domain.py', 'database.py']:
        path = args.baseline / name
        original[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    app = (args.baseline / 'app.py').read_text(encoding='utf-8')
    app = replace_once(app, 'Actor = Annotated[str, Depends(authenticate)]',
                      'Actor = Annotated[str, Depends(authenticate)]\n\n\n'
                      'def optional_actor(request: Request, authorization: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)]):\n'
                      '    return authenticate(request, authorization) if authorization is not None else None')
    rate = "    rate_limit('rpc:' + actor, int(os.environ.get('RPC_PER_MINUTE', '240')))"
    app = replace_once(app, rate, rate + "\n    if body.action.startswith('comment_'):\n"
                       "        rate_limit('comments:' + actor, 60)\n"
                       "        if body.action == 'comment_create': rate_limit('comment-create:' + actor, 8)")
    route = (backend / 'app.py').read_text(encoding='utf-8').split("@app.post('/v1/comments/query')", 1)
    assert len(route) == 2
    app += "\n\n@app.post('/v1/comments/query')" + route[1]
    (destination / 'app.py').write_text(app, encoding='utf-8', newline='\n')
    domain = (args.baseline / 'domain.py').read_text(encoding='utf-8')
    anchor = "    require(not (set(p) & {'account_id', 'actor_id', 'sender_id', 'type', 'status'}), message='身份和业务类型必须由服务器确定。')"
    domain = replace_once(domain, anchor, anchor + "\n    if action.startswith('comment_'):\n"
                          "        from comment_service import dispatch as comment_dispatch\n"
                          "        return comment_dispatch(conn, actor, action, p, before_action)")
    (destination / 'domain.py').write_text(domain, encoding='utf-8', newline='\n')
    database = (args.baseline / 'database.py').read_text(encoding='utf-8')
    anchor = "        conn.execute(Path(__file__).with_name('schema.sql').read_text(encoding='utf-8'))"
    database = replace_once(database, anchor, anchor + "\n        for path in sorted(Path(__file__).with_name('migrations').glob('*.sql')):\n"
                            "            conn.execute(path.read_text(encoding='utf-8'))")
    (destination / 'database.py').write_text(database, encoding='utf-8', newline='\n')
    for name in ['schema.sql', 'collection_catalog.json', 'requirements.lock']:
        shutil.copy2(args.baseline / name, destination / name)
    shutil.copy2(args.baseline / 'test_backend.py', destination / 'tests/test_backend.py')
    for name in ['comment_service.py', 'migrations/003_bank_comments.sql', 'tests/test_comments.py']:
        shutil.copy2(backend / name, destination / name)
    deploy_files = ['app.py', 'domain.py', 'database.py', 'comment_service.py', 'migrations/003_bank_comments.sql']
    manifest = {'baseline_sha256': original, 'files': {name: hashlib.sha256((destination / name).read_bytes()).hexdigest() for name in deploy_files}}
    (destination / 'comments-release.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print('Prepared comments-only release:', destination)
    print('Files to activate:', ', '.join(deploy_files))


if __name__ == '__main__': main()
