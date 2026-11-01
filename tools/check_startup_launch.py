"""Exercise the real autoload/main-scene startup, then verify X ends the process."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    folder = Path(tempfile.mkdtemp(prefix='workbench-check-startup-', dir=root / '.godot_appdata'))
    project = folder / 'project'
    project.mkdir()
    text = (root / 'project.godot').read_text(encoding='utf-8')
    anchor = 'BackendProvider="*res://scripts/backend_provider.gd"'
    assert text.count(anchor) == 1
    text = text.replace(anchor, anchor + '\nStartupProbe="*res://tools/fixtures/startup_launch_probe.gd"')
    (project / 'project.godot').write_text(text, encoding='utf-8')
    for name in ['scripts', 'scenes', 'assets', 'data', 'fonts', 'shaders', 'themes', 'tools', 'addons']:
        os.symlink(root / name, project / name, target_is_directory=True)
    (project / '.godot').mkdir()
    os.symlink(root / '.godot/imported', project / '.godot/imported', target_is_directory=True)
    shutil.copy2(root / '.godot/global_script_class_cache.cfg', project / '.godot/global_script_class_cache.cfg')
    env = os.environ.copy()
    env.pop('HEGONG_BACKEND_DISABLED', None)
    env['HEGONG_BACKEND_LIVE_TEST'] = '1'  # Allow the normal startup path in a headless renderer.
    env['HEGONG_API_URL'] = 'https://startup-login.test'  # Never contact production.
    for name in ['APPDATA', 'LOCALAPPDATA']:
        path = folder / name.lower()
        path.mkdir()
        env[name] = str(path)
    result = subprocess.run([str(args.godot), '--path', str(project), '--headless',
                             '--rendering-method', 'gl_compatibility', '--log-file', str(folder / 'startup.log')],
                            env=env, capture_output=True, timeout=40)
    output = (result.stdout + result.stderr).decode('utf-8', errors='replace')
    print(output)
    print('Isolated real-startup evidence:', folder)
    assert result.returncode == 0 and 'NORMAL STARTUP LOGIN: PASS' in output and 'ERROR:' not in output


if __name__ == '__main__':
    main()
