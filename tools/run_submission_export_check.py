"""Smoke-test the packaged Windows executable with isolated saves and no backend."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe',required=True,type=Path)
    parser.add_argument('--keep-open',action='store_true',help='Leave the isolated release window open for visual inspection')
    args=parser.parse_args()
    fixture=Path(tempfile.mkdtemp(prefix='workbench-check-submission-export-',dir=ROOT/'.godot_appdata'))
    env=os.environ.copy();env['HEGONG_BACKEND_DISABLED']='1';env['HEGONG_SUBMISSION_DIAGNOSTICS']='1'
    for key in ['APPDATA','LOCALAPPDATA']:
        target=fixture/key.lower();target.mkdir();env[key]=str(target)
    # Release templates intentionally reject external --script/--path overrides.
    # Exercise the shipped route, packed JavaScript and real IPC handshake.
    command=[str(args.exe.resolve()),'--rendering-method','gl_compatibility']
    if not args.keep_open:command+=['--quit-after','900','--position','-10000,-10000']
    command+=['--','--open-submissions']
    if args.keep_open:
        process=subprocess.Popen(command,env=env,cwd=args.exe.resolve().parent,
                                 creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        print('Manual release inspection: isolated process',process.pid,'; saves:',fixture)
        print('No automated PASS is implied by launching the window.')
        return
    result=subprocess.run(command,env=env,cwd=args.exe.resolve().parent,capture_output=True,timeout=35,
                          creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
    log=fixture/'appdata/Godot/app_userdata/河工开物/logs/godot.log'
    output=log.read_text(encoding='utf-8',errors='replace') if log.exists() else ''
    passed=result.returncode==0 and 'SUBMISSION EDITOR READY' in output and 'remote_debugging=false' in output and 'ERROR:' not in output
    print(output);print('Packaged check log:',log)
    if not passed:raise SystemExit(1)
    print('PACKAGED SUBMISSION CHECK: PASS (real release route and renderer handshake)')

if __name__=='__main__':main()
