"""Guarded additive wishlist deployment; rollback code, never user writes."""
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

TARGET = Path('/opt/hegong/backend')
PYTHON = '/opt/hegong/venv/bin/python'
FILES = {'domain.py','wishlist_service.py','migrations/006_collection_wishlist.sql'}
PROTECTED = {'/etc/nginx/sites-available/hegong','/etc/systemd/system/hegong-backend.service','/etc/hegong/backend.env'}


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def install(source,target):
    stat = (target if target.exists() else TARGET/'domain.py').stat()
    temporary = target.with_name(target.name+'.wishlist-new')
    shutil.copyfile(source,temporary)
    temporary.chmod(stat.st_mode & 0o777)
    os.chown(temporary,stat.st_uid,stat.st_gid)
    os.replace(temporary,target)


def wait_healthy():
    for attempt in range(40):
        try:
            with urllib.request.urlopen('http://127.0.0.1:8000/health',timeout=3) as response:
                if json.load(response).get('status')=='ok': return
        except Exception: pass
        time.sleep(.5)
    raise RuntimeError('Service failed readiness checks')


def database_state():
    code = """import json,psycopg
with psycopg.connect('dbname=hegong user=hegong host=/var/run/postgresql') as conn:
 print(json.dumps({'users':conn.execute('SELECT count(*) FROM users').fetchone()[0],
 'schema_versions':[r[0] for r in conn.execute('SELECT version FROM schema_versions ORDER BY version')]}))
"""
    result = subprocess.run(['runuser','-u','hegong','--',PYTHON,'-c',code],capture_output=True,text=True,check=True)
    return json.loads(result.stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('candidate',type=Path)
    parser.add_argument('--apply',action='store_true',required=True)
    args = parser.parse_args()
    assert os.geteuid()==0
    os.umask(0o077)
    candidate = args.candidate.resolve()
    assert candidate.is_relative_to('/opt/hegong/releases')
    manifest_path = candidate/'wishlist-release.json'
    manifest = json.loads(manifest_path.read_text())
    assert set(manifest['files'])==FILES and set(manifest['protected_sha256'])==PROTECTED
    receipt = json.loads((candidate/'tests-passed.json').read_text())
    assert receipt['passed'] is True and receipt['manifest_sha256']==digest(manifest_path)
    assert receipt['database'].startswith('hegong_wishlist_') and receipt['database'].endswith('_test')
    with open('/run/lock/hegong-deploy.lock','w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        for name,value in manifest['candidate_sha256'].items():
            assert (candidate/name).resolve().is_relative_to(candidate)
            assert digest(candidate/name)==value,name
        def verify(updated=False):
            for name,original in manifest['baseline_sha256'].items():
                assert (TARGET/name).resolve().is_relative_to(TARGET)
                expected = manifest['files'].get(name,original) if updated else original
                assert digest(TARGET/name)==expected,'Production changed: '+name
            for name in FILES-set(manifest['baseline_sha256']):
                if updated: assert digest(TARGET/name)==manifest['files'][name]
                else: assert not (TARGET/name).exists(),'New file already exists: '+name
            for name,value in manifest['protected_sha256'].items():
                assert digest(Path(name))==value,'Protected configuration changed'
        verify()
        before = database_state()
        assert 6 not in before['schema_versions']
        backup = Path('/var/backups/hegong')/('wishlist-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
        backup.mkdir(mode=0o700)
        with (backup/'database.dump').open('wb') as stream:
            subprocess.run(['runuser','-u','hegong','--','pg_dump','-Fc','hegong'],stdout=stream,check=True)
        subprocess.run(['pg_restore','--list',str(backup/'database.dump')],stdout=subprocess.DEVNULL,check=True)
        shutil.copy2(TARGET/'domain.py',backup/'domain.py')
        shutil.copy2(manifest_path,backup/'wishlist-release.json')
        shutil.copy2(candidate/'tests-passed.json',backup/'tests-passed.json')
        (backup/'before.json').write_text(json.dumps(before))
        verify()
        installed = []
        try:
            for name in ['wishlist_service.py','migrations/006_collection_wishlist.sql','domain.py']:
                install(candidate/name,TARGET/name)
                installed.append(name)
            subprocess.run(['systemctl','restart','hegong-backend'],check=True)
            wait_healthy()
            after = database_state()
            assert after['schema_versions']==before['schema_versions']+[6]
            subprocess.run([PYTHON,str(candidate/'ops/smoke_wishlist_release.py'),'--output',str(backup/'https')],check=True,timeout=180)
            verify(True)
            after = database_state()
        except Exception:
            for name in reversed(installed):
                assert digest(TARGET/name)==manifest['files'][name],'Concurrent edit prevents rollback'
                if name=='domain.py': install(backup/name,TARGET/name)
                else: (TARGET/name).unlink()
            subprocess.run(['systemctl','restart','hegong-backend'],check=True)
            wait_healthy()
            # Additive schema may remain, preserving any writes made after restart.
            (backup/'activation.json').write_text(json.dumps({'status':'rolled_back','backup':str(backup)}))
            raise
        report = {'status':'activated','backup':str(backup),'files':sorted(FILES),'before':before,'after':after,
                  'https':json.loads((backup/'https/https-checks.json').read_text())}
        (backup/'activation.json').write_text(json.dumps(report,indent=2))
        print(json.dumps(report))


if __name__ == '__main__': main()
