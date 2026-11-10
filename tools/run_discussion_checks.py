"""Real loopback PostgreSQL + FastAPI + Godot, with isolated learner saves.

Requires an existing local test PostgreSQL cluster and backend dependencies.
No production endpoint, production credentials or remote deployment is used.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import time

import httpx
import psycopg
from psycopg.conninfo import conninfo_to_dict

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--visual', action='store_true')
    args = parser.parse_args()
    env = os.environ.copy()
    env.setdefault('DATABASE_URL', 'host=127.0.0.1 port=55439 dbname=hegong_comments_test user=hegong_test_owner')
    config = conninfo_to_dict(env['DATABASE_URL'])
    assert config.get('dbname', '').endswith('_test') and config.get('host') == '127.0.0.1'
    env.setdefault('CURSOR_SECRET', secrets.token_hex(32))
    env['REGISTER_PER_MINUTE'] = '10000'
    env['HEGONG_BACKEND_DISABLED'] = '1'
    log = open(ROOT / '.godot_appdata/discussion-http.log', 'w', encoding='utf-8')
    server = subprocess.Popen([sys.executable, '-m', 'uvicorn', 'app:app', '--host', '127.0.0.1', '--port', '18547'],
                              cwd=ROOT / 'backend', env=env, stdout=log, stderr=log,
                              creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
    accounts = []
    try:
        with httpx.Client(base_url='http://127.0.0.1:18547', timeout=15) as client:
            for _ in range(50):
                try:
                    if client.get('/health').status_code == 200: break
                except httpx.TransportError: pass
                time.sleep(.1)
            else: raise RuntimeError('Loopback backend did not start')
            for label in ['本机测试用户', '本机测试同学']:
                response = client.post('/v1/auth/register', json={'username': 'comments_' + secrets.token_hex(5), 'password': secrets.token_urlsafe(20), 'display_name': label})
                response.raise_for_status(); accounts.append(response.json())
            for account, college in zip(accounts, ['能源与环境工程学院', '人工智能与数据科学学院']):
                response = client.post('/v1/rpc', headers={'Authorization':'Bearer '+account['access_token']}, json={
                    'version':1,'action':'save_profile','payload':{'patch':{'college':college},'avatar_card_id':''}})
                response.raise_for_status()
            # Seed actual database records through authenticated API writes.
            for index, body in enumerate(['本条评论由本机隔离账号通过真实 API 发布，用于核对题库公共讨论的排版。',
                                          '切到同一题库的其他题目后，这里的讨论和未发布草稿应继续保留。',
                                          '回复、点赞、删除和排序会通过服务端处理，不改变答题进度。']):
                response = client.post('/v1/rpc', headers={'Authorization': 'Bearer ' + accounts[index % 2]['access_token']}, json={
                    'version':1, 'action':'comment_create', 'payload':{'target_type':'bank','target_id':'marxism','body':body,'parent_id':'','operation_id':secrets.token_hex(16)}})
                response.raise_for_status()
            session_path = ROOT / '.godot_appdata/discussion-check-session.json'
            session_path.write_text(json.dumps(accounts), encoding='utf-8')
        fixture = Path(tempfile.mkdtemp(prefix='workbench-check-comments-', dir=ROOT / '.godot_appdata'))
        for key in ['APPDATA','LOCALAPPDATA']:
            folder = fixture / key.lower(); folder.mkdir(); env[key] = str(folder)
        command = [args.godot,'--path',str(ROOT),'--rendering-method','gl_compatibility','--script','res://tools/check_bank_discussion.gd',
                   '--log-file',str(fixture/'check.log')]
        if not args.visual: command.append('--headless')
        result = subprocess.run(command, env=env, capture_output=True, timeout=150)
        output = (result.stdout + result.stderr).decode('utf-8', errors='replace')
        print(output)
        print('Isolated saves and log:', fixture)
        if result.returncode or 'ERROR:' in output or 'WORKBENCH CHECKS: PASS' not in output: raise SystemExit(1)
    finally:
        server.terminate(); server.wait(timeout=15); log.close()
        session_path = ROOT / '.godot_appdata/discussion-check-session.json'
        if session_path.exists(): session_path.unlink()
        # Remove only the exact temporary accounts created by this run.
        if accounts:
            with psycopg.connect(env['DATABASE_URL']) as conn:
                conn.execute('DELETE FROM users WHERE id=ANY(%s)', ([a['account_id'] for a in accounts],))


if __name__ == '__main__': main()
