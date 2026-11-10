"""Activate the tested submission release with code/DB/nginx backups and rollback."""
import argparse
from datetime import datetime,timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import urllib.request

TARGET=Path('/opt/hegong/backend')
NGINX=Path('/etc/nginx/sites-available/hegong')
FILES={'app.py','domain.py','requirements.lock','submission_service.py','submission_document.py','publication_rewards.py',
       'migrations/002_submissions.sql','ops/grant_reviewer.py','ops/cleanup_submission_assets.py','ops/deliver_publication_rewards.py'}
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None
def healthy():
    try:
        for endpoint,key,value in [('/health','status','ok'),('/v1/articles','ok',True)]:
            with urllib.request.urlopen('http://127.0.0.1:8000'+endpoint,timeout=3) as response:
                if json.load(response).get(key)!=value:return False
        request=urllib.request.Request('http://127.0.0.1:8000/v1/comments/query',data=json.dumps({'action':'comment_list','payload':{'target_type':'bank','target_id':'marxism','limit':1}}).encode(),headers={'Content-Type':'application/json'})
        with urllib.request.urlopen(request,timeout=3) as response:return json.load(response).get('ok') is True
    except Exception:return False
def install(source,target):
    target.parent.mkdir(parents=True,exist_ok=True,mode=0o755)
    target.parent.chmod(0o755)
    temporary=target.with_name(target.name+'.submissions-new')
    shutil.copyfile(source,temporary);temporary.chmod(0o644);os.replace(temporary,target)

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('candidate',type=Path)
    parser.add_argument('--apply',action='store_true',required=True);args=parser.parse_args()
    assert os.geteuid()==0;os.umask(0o077)
    candidate=args.candidate.resolve();assert candidate.is_relative_to('/opt/hegong/releases')
    manifest=json.loads((candidate/'submissions-release.json').read_text())
    assert set(manifest['files'])==FILES and set(manifest['baseline_sha256'])==FILES
    with open('/run/lock/hegong-deploy.lock','w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        for name,expected in manifest['files'].items():assert digest(candidate/name)==expected,name
        assert digest(candidate/'nginx.conf')==manifest['nginx_candidate']
        def verify():
            for name,expected in {**manifest['baseline_sha256'],**manifest['guard_sha256']}.items():assert digest(TARGET/name)==expected,'Server changed: '+name
            assert digest(NGINX)==manifest['nginx_baseline'],'Nginx changed since review'
        verify()
        backup=Path('/var/backups/hegong')/('submissions-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
        backup.mkdir(mode=0o700)
        with (backup/'database.dump').open('wb') as out:subprocess.run(['runuser','-u','hegong','--','pg_dump','-Fc','hegong'],stdout=out,check=True)
        subprocess.run(['pg_restore','--list',str(backup/'database.dump')],stdout=subprocess.DEVNULL,check=True)
        for name,expected in manifest['baseline_sha256'].items():
            if expected is not None:
                (backup/name).parent.mkdir(parents=True,exist_ok=True);shutil.copy2(TARGET/name,backup/name)
        shutil.copy2(NGINX,backup/'nginx.conf');shutil.copy2(candidate/'submissions-release.json',backup/'submissions-release.json')
        installed=[];nginx_changed=False
        try:
            verify()
            for name in sorted(FILES):install(candidate/name,TARGET/name);installed.append(name)
            install(candidate/'nginx.conf',NGINX);nginx_changed=True
            subprocess.run(['nginx','-t'],check=True)
            subprocess.run(['systemctl','restart','hegong-backend'],check=True)
            for _ in range(40):
                if healthy():break
                time.sleep(.5)
            else:raise RuntimeError('Post-activation health checks failed')
            subprocess.run(['systemctl','reload','nginx'],check=True)
        except Exception:
            for name in installed:
                assert digest(TARGET/name)==manifest['files'][name],'Concurrent change prevents rollback: '+name
                if (backup/name).exists():install(backup/name,TARGET/name)
                else:(TARGET/name).unlink()
            if nginx_changed:
                assert digest(NGINX)==manifest['nginx_candidate'];install(backup/'nginx.conf',NGINX)
            subprocess.run(['systemctl','restart','hegong-backend'],check=True)
            subprocess.run(['nginx','-t'],check=True);subprocess.run(['systemctl','reload','nginx'],check=True)
            # Additive migration is retained: never restore over new user writes.
            raise
        result={'status':'activated','backup':str(backup),'files':sorted(FILES),'nginx':'scoped upload and RPC limits'}
        (backup/'activation.json').write_text(json.dumps(result,indent=2))
        print(json.dumps(result))

if __name__=='__main__':main()
