"""Prepare a scoped capacity/college update from the downloaded live baseline."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def replace_once(text, before, after):
    if text.count(before) != 1: raise RuntimeError('Live baseline changed; review required')
    return text.replace(before, after, 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline',type=Path); parser.add_argument('destination',type=Path)
    args = parser.parse_args(); base=args.baseline; dest=args.destination
    source = Path(__file__).resolve().parents[1]
    dest.mkdir(parents=True, exist_ok=False); (dest/'ops').mkdir(); (dest/'migrations').mkdir(); (dest/'tests').mkdir()
    local = (source/'app.py').read_text(encoding='utf-8')
    app = (base/'app.py').read_text(encoding='utf-8')
    old_handler = 'async def domain_error(request, error):\n'
    new_handler = local[local.index(old_handler):local.index('    return JSONResponse',local.index(old_handler))]
    app = replace_once(app,old_handler,new_handler)
    app = replace_once(app,"    limit = 9 * 1024 * 1024 if request.url.path == '/v1/submission-assets'", "    limit = 16 * 1024 * 1024 if request.url.path == '/v1/comments/write' else 9 * 1024 * 1024 if request.url.path == '/v1/submission-assets'")
    app += '\n\n' + local[local.index("@app.post('/v1/comments/write')"):]
    (dest/'app.py').write_text(app,encoding='utf-8',newline='\n')
    files = ['app.py','comment_service.py','comment_capacity.py','migrations/004_discussion_capacity.sql','ops/deliver_comment_alerts.py']
    for name in files[1:]: shutil.copy2(source/name,dest/name)
    shutil.copy2(source/'tests/test_comments.py',dest/'tests/test_comments.py')
    shutil.copy2(source/'ops/comment-alerts.env.example',dest/'comment-alerts.env')
    nginx = (base/'hegong').read_text(encoding='utf-8')
    location = '''    location = /v1/comments/write {
        client_max_body_size 16m;
        limit_req zone=hegong_api burst=200 nodelay;
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 45s;
    }
'''
    nginx = replace_once(nginx,'    location = /v1/rpc {',location+'    location = /v1/rpc {')
    (dest/'nginx.conf').write_text(nginx,encoding='utf-8',newline='\n')
    manifest = {'files':{name:digest(dest/name) for name in files},
                'baseline_sha256':{name:digest(base/name) if (base/name).exists() else None for name in files},
                'nginx_baseline':digest(base/'hegong'),'nginx_candidate':digest(dest/'nginx.conf')}
    (dest/'capacity-release.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print('Prepared:',dest)


if __name__=='__main__': main()
