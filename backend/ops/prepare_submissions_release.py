"""Build a submission-only release against an exact downloaded server baseline."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def replace_once(text, old, new):
    if text.count(old)!=1:raise RuntimeError('Server baseline changed; review the intended patch')
    return text.replace(old,new,1)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline',type=Path);parser.add_argument('destination',type=Path)
    args=parser.parse_args();base=args.baseline;dest=args.destination
    source=Path(__file__).resolve().parents[1]
    shutil.copytree(base,dest)
    (dest/'ops').mkdir(exist_ok=True)
    local=(source/'app.py').read_text(encoding='utf-8')
    app=(base/'app.py').read_text(encoding='utf-8')
    app=replace_once(app,'import hashlib\n','import hashlib\nimport json\n')
    app=replace_once(app,'from fastapi.responses import JSONResponse\n','from fastapi.responses import JSONResponse, Response\n')
    app=replace_once(app,'    if length > 256 * 1024:',"    limit = 9 * 1024 * 1024 if request.url.path == '/v1/submission-assets' else 1024 * 1024 if request.url.path == '/v1/rpc' else 256 * 1024\n    if length > limit:")
    bounded=local[local.index('async def bounded_json'):local.index('def rate_limit')]
    app=replace_once(app,'def rate_limit',bounded+'def rate_limit')
    routes=local[local.index("@app.post('/v1/submission-assets')"):local.index('def check_session_after_lock')]
    app=replace_once(app,'def check_session_after_lock',routes+'def check_session_after_lock')
    (dest/'app.py').write_text(app,encoding='utf-8',newline='\n')
    domain=(base/'domain.py').read_text(encoding='utf-8')
    domain=replace_once(domain,'    prepare_locks(conn, actor, action, p)',
        "    if action.startswith(('submission_', 'article_')) or action == 'publication_review':\n"
        "        from submission_service import dispatch as submission_dispatch\n"
        "        return submission_dispatch(conn, actor, action, p, before_action)\n"
        "    prepare_locks(conn, actor, action, p)")
    (dest/'domain.py').write_text(domain,encoding='utf-8',newline='\n')
    lock=(base/'requirements.lock').read_text(encoding='utf-8').rstrip()+'\npillow==13.0.0\n'
    (dest/'requirements.lock').write_text(lock,encoding='utf-8',newline='\n')
    files=['app.py','domain.py','requirements.lock','submission_service.py','submission_document.py','publication_rewards.py',
           'migrations/002_submissions.sql','ops/grant_reviewer.py','ops/cleanup_submission_assets.py','ops/deliver_publication_rewards.py']
    for name in files[3:]:shutil.copy2(source/name,dest/name)
    for name in ['test_comments.py','test_submissions.py']:shutil.copy2(source/'tests'/name,dest/'tests'/name)
    nginx=(base/'nginx.conf').read_text(encoding='utf-8')
    generic=nginx[nginx.index('    location / {\n'):nginx.rindex('\n}')]
    additions=''
    for endpoint,limit in [('/v1/submission-assets','9m'),('/v1/rpc','1m')]:
        additions+=generic.replace('    location / {',f'    location = {endpoint} {{\n        client_max_body_size {limit};',1)+'\n'
    nginx=replace_once(nginx,'    location / {\n',additions+'    location / {\n')
    (dest/'nginx.conf').write_text(nginx,encoding='utf-8',newline='\n')
    guards=['database.py','schema.sql','collection_catalog.json','comment_service.py','migrations/003_bank_comments.sql']
    manifest={'files':{name:digest(dest/name) for name in files},
              'baseline_sha256':{name:digest(base/name) if (base/name).exists() else None for name in files},
              'guard_sha256':{name:digest(base/name) for name in guards},
              'nginx_baseline':digest(base/'nginx.conf'),'nginx_candidate':digest(dest/'nginx.conf'),'pillow':'13.0.0'}
    (dest/'submissions-release.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print('Prepared:',dest);print('Deployment files:',', '.join(files))

if __name__=='__main__':main()
