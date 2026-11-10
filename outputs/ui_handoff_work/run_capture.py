import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
GODOT = Path(r'C:\Users\Legion\Desktop\工具\游戏创作\Godot_v4.6.2-stable_win64_console.exe')
for part in sys.argv[1:] or ['basic', 'account', 'social', 'wallet', 'cards']:
    isolated = Path(tempfile.mkdtemp(prefix='workbench-check-art-', dir=ROOT / '.godot_appdata'))
    env = os.environ.copy()
    env['HEGONG_BACKEND_DISABLED'] = '1'
    for key in ['APPDATA', 'LOCALAPPDATA']:
        folder = isolated / key.lower()
        folder.mkdir()
        env[key] = str(folder)
    command = [str(GODOT), '--path', str(ROOT), '--rendering-method', 'gl_compatibility',
               '--script', 'res://outputs/ui_handoff_work/' + ('submissions.gd' if part == 'submissions' else 'capture.gd'), '--log-file', str(isolated / 'capture.log'), '--', part]
    print('START', part, flush=True)
    try:
        result = subprocess.run(command, env=env, capture_output=True, timeout=160,
                                creationflags=subprocess.CREATE_NO_WINDOW)
        output = (result.stdout + result.stderr).decode('utf-8', errors='replace')
        (ROOT / 'outputs/ui_handoff_work' / (part + '.log')).write_text(output, encoding='utf-8')
        print(output, flush=True)
    except subprocess.TimeoutExpired as error:
        output = (error.stdout or b'') + (error.stderr or b'')
        print(output.decode('utf-8', errors='replace'), flush=True)
        print('TIMEOUT', part, flush=True)
