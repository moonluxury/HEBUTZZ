"""Exercise real HTTPS wishlist persistence using only two temporary identities."""
import argparse
import json
from pathlib import Path
import secrets
import subprocess
import sys
import httpx


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    accounts, credentials, checks = [], [], []
    cleanup = None
    run = secrets.token_hex(6)
    def check(condition,label):
        if not condition: raise RuntimeError('HTTPS check failed: '+label)
        checks.append(label)
    with httpx.Client(base_url='https://39.107.44.18',timeout=20,follow_redirects=False) as client:
        def rpc(actor,action,expected=200,**payload):
            if action in {'wishlist_update','request_friend','respond_request','relationship'}:
                payload.setdefault('operation_id',secrets.token_hex(16))
            response = client.post('/v1/rpc',headers={'Authorization':'Bearer '+actor['access_token']} if actor else {},
                                   json={'version':1,'action':action,'payload':payload})
            check(response.status_code==expected,action+' HTTP '+str(expected))
            return response.json()
        try:
            check(client.get('/health').json().get('status')=='ok','TLS and health')
            for suffix in ['a','b']:
                username = 'wishcheck_'+run+suffix
                password = secrets.token_urlsafe(24)
                response = client.post('/v1/auth/register',json={'username':username,'password':password})
                check(response.status_code==200,'Temporary registration '+suffix)
                value = response.json()
                accounts.append({'id':value['account_id'],'username':username})
                (args.output/'temporary-accounts.json').write_text(json.dumps({'accounts':accounts}))
                credentials.append({**value,'username':username,'password':password})
            a,b = credentials
            rpc(None,'wishlist_load',401)
            check(rpc(a,'wishlist_load')['initialized'] is False,'New account has no fabricated wishes')
            operation = secrets.token_hex(16)
            first = rpc(a,'wishlist_update',expected_revision=0,changes={'0001':True,'0003':True},operation_id=operation)
            check(first['card_ids']==['0001','0003'],'Add wishlist cards')
            second = client.post('/v1/auth/login',json={'username':a['username'],'password':a['password']}).json()
            check(rpc(second,'wishlist_load')['card_ids']==['0001','0003'],'Second session reads same persisted list')
            rpc(a,'wishlist_update',expected_revision=1,changes={'0001':False})
            replay = rpc(a,'wishlist_update',expected_revision=0,changes={'0001':True,'0003':True},operation_id=operation)
            check(replay==first and rpc(second,'wishlist_load')['card_ids']==['0003'],'Old retry does not resurrect a removed card')
            conflict = rpc(a,'wishlist_update',409,expected_revision=0,changes={'0002':True})
            check(conflict['code']=='wishlist_conflict','Stale revisions rejected')
            check(rpc(b,'wishlist_load')['card_ids']==[],'Accounts remain isolated')
            rpc(b,'wishlist',403,peer_id=a['account_id'])
            request = rpc(a,'request_friend',peer_id=b['account_id'])['request']
            rpc(b,'respond_request',request_id=request['id'],decision='accept')
            projected = rpc(b,'wishlist',peer_id=a['account_id'])
            check(projected['card_ids']==['0003'] and 'inventory' not in projected,'Friend sees the same list without inventory disclosure')
            rpc(a,'wishlist_update',400,expected_revision=2,changes={'unknown':True})
            rpc(a,'relationship',peer_id=b['account_id'],operation='block')
            rpc(b,'wishlist',403,peer_id=a['account_id'])
            rpc(a,'wishlist',403,peer_id=b['account_id'])
            check(client.get('/v1/articles').json().get('ok') is True,'Existing articles remain available')
        finally:
            if accounts:
                result = subprocess.run(['runuser','-u','hegong','--',sys.executable,str(Path(__file__).with_name('wishlist_smoke_cleanup.py'))],
                                        input=json.dumps({'accounts':accounts}),text=True,capture_output=True,timeout=30)
                if result.returncode: raise RuntimeError('Exact temporary-account cleanup failed')
                cleanup = json.loads(result.stdout)
            (args.output/'https-checks.json').write_text(json.dumps({'checks_passed':len(checks),'checks':checks,'cleanup':cleanup},indent=2))
    print(json.dumps({'passed':True,'checks':len(checks),'cleanup':cleanup}))


if __name__ == '__main__': main()
