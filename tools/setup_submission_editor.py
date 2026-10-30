"""Install the pinned Windows CEF runtime without changing system settings.

The runtime is a build dependency, excluded from Git. Godot exports it alongside
the Windows executable. Only the Windows portion of the official ZIP is fetched.
"""
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import urllib.request
import zipfile

VERSION = '2.1.1'
URL = f'https://github.com/dsh0416/godot-cef/releases/download/v{VERSION}/godot_cef-store-v{VERSION}.zip'
ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'addons' / 'godot_cef'


class RemoteArchive(io.RawIOBase):
    def __init__(self):
        with urllib.request.urlopen(urllib.request.Request(URL, method='HEAD'), timeout=45) as response:
            self.url = response.url
            self.length = int(response.headers['Content-Length'])
        self.position = 0
        self.cache_offset = 0
        self.cache = b''

    def seekable(self): return True
    def readable(self): return True
    def tell(self): return self.position

    def seek(self, offset, whence=0):
        self.position = offset if whence == 0 else self.position + offset if whence == 1 else self.length + offset
        return self.position

    def read(self, count=-1):
        count = self.length - self.position if count < 0 else min(count, self.length - self.position)
        if count <= 0: return b''
        relative = self.position - self.cache_offset
        if relative >= 0 and relative + count <= len(self.cache):
            data = self.cache[relative:relative + count]
        else:
            end = min(self.length, self.position + max(count, 65536)) - 1
            request = urllib.request.Request(self.url, headers={'Range': f'bytes={self.position}-{end}'})
            with urllib.request.urlopen(request, timeout=180) as response:
                if response.status != 206: raise RuntimeError('The vendor server did not honor an archive range request')
                self.cache = response.read()
            self.cache_offset = self.position
            data = self.cache[:count]
        self.position += len(data)
        return data


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    manifest_path = DEST / 'runtime-manifest.json'
    previous = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    files = {}
    prefix = 'dist/addons/godot_cef/'
    with zipfile.ZipFile(RemoteArchive()) as archive:
        for info in archive.infolist():
            if not info.filename.startswith(prefix) or info.is_dir(): continue
            relative = info.filename[len(prefix):]
            if '..' in PurePosixPath(relative).parts or PurePosixPath(relative).is_absolute(): raise ValueError('Invalid vendor archive path')
            selected = relative.startswith(('bin/x86_64-pc-windows-msvc/', 'icons/')) or relative == 'godot_cef.gdextension'
            if not selected: continue
            if '/locales/' in relative and PurePosixPath(relative).name not in ['en-US.pak', 'zh-CN.pak']: continue
            target = DEST / relative
            old_hash = previous.get('files', {}).get(relative, {}).get('sha256')
            if target.exists() and old_hash and hashlib.sha256(target.read_bytes()).hexdigest() == old_hash:
                files[relative] = previous['files'][relative]
                continue
            print('Installing', relative, info.file_size, flush=True)
            content = archive.read(info)  # ZIP CRC also checks each selected member.
            target.parent.mkdir(parents=True, exist_ok=True)
            temporary = target.with_suffix(target.suffix + '.part')
            temporary.write_bytes(content)
            temporary.replace(target)
            files[relative] = {'bytes': len(content), 'sha256': hashlib.sha256(content).hexdigest()}
            manifest_path.write_text(json.dumps({'version': VERSION, 'source': URL, 'files': files}, indent=2), encoding='utf-8')
    # Keep CEF's Vulkan loader and helper runtime out of the game's executable
    # directory, and retain the manifest's relative library paths after export.
    extension = DEST / 'godot_cef.gdextension'
    source = extension.read_text(encoding='utf-8')
    lines = source.splitlines()
    windows = False
    for index, line in enumerate(lines):
        if line.startswith('windows.x86_64 = {'): windows = True
        elif windows and line.strip() == '}': windows = False
        elif windows:
            lines[index] = line.replace(': ""', ': "addons/godot_cef/bin/x86_64-pc-windows-msvc"')
    extension.write_text('\n'.join(lines)+'\n', encoding='utf-8')
    from prepare_submission_runtime import prepare
    prepare()
    print('CEF runtime installed:', sum(item['bytes'] for item in files.values()), 'bytes')


if __name__ == '__main__': main()
