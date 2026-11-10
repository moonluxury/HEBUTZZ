"""Activate the reviewed capacity/college release with scoped nginx and mail jobs."""
import argparse
from datetime import datetime, timezone
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
FILES={'app.py','comment_service.py','comment_capacity.py','migrations/004_discussion_capacity.sql','ops/deliver_comment_alerts.py'}


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def install(source, target):
    if not target.parent.exists(): target.parent.mkdir(mode=0o755); target.parent.chmod(0o755)
    temporary=target.with_name(target.name+'.capacity-new')
    shutil.copyfile(source,temporary); temporary.chmod(0o644); os.replace(temporary,target)


def healthy():
    try:
        query={'version':1,'action':'comment_list','payload':{'target_type':'bank','target_id':'marxism','limit':1}}
        request=urllib.request.Request('http://127.0.0.1:8000/v1/comments/query',data=json.dumps(query).encode(),headers={'Content-Type':'application/json'})
        with urllib.request.urlopen(request,timeout=5) as response: body=json.load(response)
        return body.get('ok') is True and 'can_publish' in body
    except Exception: return False


def main():
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('candidate',type=Path)
    parser.add_argument('--apply',action='store_true',required=True); args=parser.parse_args()
    assert os.geteuid()==0; os.umask(0o077)
    candidate=args.candidate.resolve(); assert candidate.is_relative_to('/opt/hegong/releases')
    manifest=json.loads((candidate/'capacity-release.json').read_text())
    assert set(manifest['files'])==FILES and set(manifest['baseline_sha256'])==FILES
    with open('/run/lock/hegong-deploy.lock','w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        for name,value in manifest['files'].items(): assert digest(candidate/name)==value,name
        assert digest(candidate/'nginx.conf')==manifest['nginx_candidate']
        def verify():
            for name,value in manifest['baseline_sha256'].items(): assert digest(TARGET/name)==value,'Live file changed: '+name
            assert digest(NGINX)==manifest['nginx_baseline'],'Nginx changed'
        verify()
        backup=Path('/var/backups/hegong')/('discussion-capacity-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
        backup.mkdir(mode=0o700)
        with (backup/'database.dump').open('wb') as output: subprocess.run(['runuser','-u','hegong','--','pg_dump','-Fc','hegong'],stdout=output,check=True)
        subprocess.run(['pg_restore','--list',str(backup/'database.dump')],stdout=subprocess.DEVNULL,check=True)
        for name,value in manifest['baseline_sha256'].items():
            if value is not None:
                (backup/name).parent.mkdir(parents=True,exist_ok=True); shutil.copy2(TARGET/name,backup/name)
        shutil.copy2(NGINX,backup/'nginx.conf'); shutil.copy2(candidate/'capacity-release.json',backup/'capacity-release.json')
        installed=[]; nginx_changed=False
        try:
            verify()
            for name in sorted(FILES): install(candidate/name,TARGET/name); installed.append(name)
            install(candidate/'nginx.conf',NGINX); nginx_changed=True
            subprocess.run(['nginx','-t'],check=True)
            subprocess.run(['systemctl','restart','hegong-backend'],check=True)
            for _ in range(40):
                if healthy(): break
                time.sleep(.5)
            else: raise RuntimeError('Capacity route verification failed')
            subprocess.run(['systemctl','reload','nginx'],check=True)
        except Exception:
            for name in installed:
                assert digest(TARGET/name)==manifest['files'][name],'Concurrent change prevents rollback'
                if (backup/name).exists(): install(backup/name,TARGET/name)
                else: (TARGET/name).unlink()
            if nginx_changed: install(backup/'nginx.conf',NGINX)
            subprocess.run(['systemctl','restart','hegong-backend'],check=True)
            subprocess.run(['nginx','-t'],check=True); subprocess.run(['systemctl','reload','nginx'],check=True)
            # Preserve all user data; never restore the DB over concurrent writes.
            raise
        config=Path('/etc/hegong/comment-alerts.env')
        if not config.exists():
            shutil.copyfile(candidate/'comment-alerts.env',config); config.chmod(0o640); shutil.chown(config,user='root',group='hegong')
        service=Path('/etc/systemd/system/hegong-comment-alerts.service')
        timer=Path('/etc/systemd/system/hegong-comment-alerts.timer')
        assert not service.exists() and not timer.exists(), 'Review existing mail job before changing it'
        service.write_text('''[Unit]
Description=Hegong owner-only discussion capacity mail
After=postgresql.service network-online.target
[Service]
Type=oneshot
User=hegong
Group=hegong
WorkingDirectory=/opt/hegong/backend
EnvironmentFile=/etc/hegong/backend.env
EnvironmentFile=/etc/hegong/comment-alerts.env
ExecStart=/opt/hegong/venv/bin/python /opt/hegong/backend/ops/deliver_comment_alerts.py
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
UMask=0077
TimeoutStartSec=300
''')
        timer.write_text('''[Unit]
Description=Check discussion capacity mail outbox
[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Unit=hegong-comment-alerts.service
[Install]
WantedBy=timers.target
''')
        service.chmod(0o644); timer.chmod(0o644)
        subprocess.run(['systemctl','daemon-reload'],check=True)
        subprocess.run(['systemctl','enable','--now','hegong-comment-alerts.timer'],check=True)
        report={'status':'activated','backup':str(backup),'mail':'outbox timer installed; SMTP credentials required'}
        (backup/'activation.json').write_text(json.dumps(report,indent=2))
        print(json.dumps(report))


if __name__=='__main__': main()
