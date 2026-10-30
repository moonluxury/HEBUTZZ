"""Prepare the pinned CEF binaries without their forced Windows console logging.

The vendor's gdcef.dll and gdcef_helper.exe each share one ASCII switch literal
between their startup call sites. Replace that same-length literal only after
checking the exact upstream hash. No instructions, offsets or security flags
are changed. A separate runtime directory preserves already-running clients.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil

ROOT=Path(__file__).resolve().parents[1]
ADDON=ROOT/'addons/godot_cef'
PLATFORM='x86_64-pc-windows-msvc'
QUIET=PLATFORM+'-quiet'
OLD=b'enable-logging=stderr'
NEW=b'disable-logging=quiet'
PINNED={
    'gdcef.dll':'736df5295c18e15a0cdec6001f6cc6f4faacd67137409481beb767ed4e900b00',
    'gdcef_helper.exe':'bec363209c2415613fc548d62e56b0c5bcfd908af7a31730129b2a49f2bde62c',
}

def prepare():
    manifest_path=ADDON/'runtime-manifest.json'
    manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
    if manifest['version']!='2.1.1':raise RuntimeError('Review the console patch for this new CEF version')
    assert len(OLD)==len(NEW)
    changes={}
    for relative,record in manifest['files'].items():
        prefix='bin/'+PLATFORM+'/'
        if not relative.startswith(prefix):continue
        tail=relative[len(prefix):];source=ADDON/relative
        target=ADDON/'bin'/QUIET/tail
        target.parent.mkdir(parents=True,exist_ok=True)
        if tail in PINNED:
            content=source.read_bytes();before=hashlib.sha256(content).hexdigest()
            if before!=PINNED[tail] or before!=record['sha256'] or content.count(OLD)!=1:
                raise RuntimeError('Unexpected vendor binary; refusing to patch '+tail)
            content=content.replace(OLD,NEW);after=hashlib.sha256(content).hexdigest()
            if not target.exists() or hashlib.sha256(target.read_bytes()).hexdigest()!=after:
                temporary=target.with_suffix('.part');temporary.write_bytes(content);temporary.replace(target)
            changes[tail]={'upstream_sha256':before,'patched_sha256':after,'replacement_count':1}
        elif not target.exists():
            try:os.link(source,target)
            except OSError:shutil.copy2(source,target)
        elif target.stat().st_size!=record['bytes']:
            raise RuntimeError('Unexpected runtime file: '+str(target))
    extension=ADDON/'godot_cef.gdextension'
    content=extension.read_text(encoding='utf-8').replace(PLATFORM+'-quiet',PLATFORM).replace(PLATFORM,QUIET)
    extension.write_text(content,encoding='utf-8',newline='\n')
    manifest['local_patch']={'id':'windows-no-console-v1','runtime_directory':'bin/'+QUIET,'binaries':changes}
    manifest_path.write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    print('Prepared console-free CEF runtime:',QUIET)

if __name__=='__main__':prepare()
