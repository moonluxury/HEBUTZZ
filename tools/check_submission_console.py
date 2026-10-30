"""Launch the GUI exactly without inherited stdio and reject console descendants.

Do not use CREATE_NO_WINDOW or stdout/stderr redirection for the application:
those can hide this bug. Only the read-only process inventory helper is hidden.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT=Path(__file__).resolve().parents[1]

def processes():
    command='Get-CimInstance Win32_Process | Select-Object Name,ProcessId,ParentProcessId | ConvertTo-Json -Compress'
    result=subprocess.run(['powershell.exe','-NoProfile','-Command',command],capture_output=True,text=True,
                          creationflags=subprocess.CREATE_NO_WINDOW,check=True,timeout=10)
    return json.loads(result.stdout)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    mode=parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--godot',type=Path);mode.add_argument('--exe',type=Path)
    args=parser.parse_args()
    if os.name!='nt':raise SystemExit('This is a Windows GUI regression check')
    executable=(args.godot or args.exe).resolve()
    if 'console' in executable.name.lower():raise SystemExit('Use the GUI executable, not the console wrapper')
    fixture=Path(tempfile.mkdtemp(prefix='workbench-check-console-',dir=ROOT/'.godot_appdata'))
    env=os.environ.copy();env['HEGONG_BACKEND_DISABLED']='1';env['HEGONG_SUBMISSION_DIAGNOSTICS']='1'
    for key in ['APPDATA','LOCALAPPDATA']:
        path=fixture/key.lower();path.mkdir();env[key]=str(path)
    command=[str(executable)]
    if args.godot:command+=['--path',str(ROOT)]
    command+=['--rendering-method','gl_compatibility','--position','-10000,-10000','--quit-after','1500','--','--open-submissions']
    process=subprocess.Popen(command,env=env,cwd=ROOT if args.godot else executable.parent,
                             creationflags=subprocess.DETACHED_PROCESS,close_fds=True)
    samples=[];owned={process.pid};console_pids=set();ready=False;log_text=''
    try:
        # Keep watching after renderer startup to include CEF utility processes.
        for _ in range(8):
            time.sleep(1)
            current=processes()
            for _ in range(5):
                owned.update(p['ProcessId'] for p in current if p['ParentProcessId'] in owned)
            descendants=[p for p in current if p['ProcessId'] in owned]
            console_pids.update(p['ProcessId'] for p in descendants if p['Name'].lower() in {'conhost.exe','openconsole.exe'})
            samples.append({'consoles':len(console_pids),'cef_helpers':sum(p['Name']=='gdcef_helper.exe' for p in descendants)})
            log=fixture/'appdata/Godot/app_userdata/河工开物/logs/godot.log'
            if log.exists():log_text=log.read_text(encoding='utf-8',errors='replace')
            ready=ready or 'SUBMISSION EDITOR READY' in log_text
        if not ready or console_pids or 'ERROR:' in log_text:
            raise AssertionError(f'Renderer ready={ready}, console descendants={len(console_pids)}; see {fixture}')
        print('SUBMISSION GUI CONSOLE CHECK: PASS (editor ready; zero console processes)')
    finally:
        if process.poll() is None:process.terminate();process.wait(timeout=10)
        report={'renderer_ready':ready,'console_count':len(console_pids),'samples':samples}
        (fixture/'result.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
        print('Console audit:',fixture/'result.json')

if __name__=='__main__':main()
