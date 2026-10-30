"""Verify deployed HTTPS submission endpoints without publishing or awarding credits."""
import argparse
import base64
import io
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile

import httpx
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host',required=True);parser.add_argument('--identity',required=True)
    parser.add_argument('--known-hosts',required=True);parser.add_argument('--cleanup',required=True)
    args=parser.parse_args()
    folder=Path(tempfile.mkdtemp(prefix='submissions-live-',dir=ROOT/'.godot_appdata'))
    identities=[];passed=[]
    def check(condition,label):
        if not condition:raise AssertionError(label)
        passed.append(label)
    def uid():return secrets.token_hex(16)
    ssh=['ssh','-i',args.identity,'-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-o','UserKnownHostsFile='+args.known_hosts,args.host,
         'runuser','-u','hegong','--','/opt/hegong/venv/bin/python',args.cleanup]
    try:
        with httpx.Client(base_url='https://39.107.44.18',timeout=30,follow_redirects=False) as client:
            check(client.get('/health').json().get('status')=='ok','HTTPS health and certificate validation')
            accounts=[];suffix=secrets.token_hex(6)
            for letter in ['a','b']:
                username='submissioncheck_'+suffix+letter
                response=client.post('/v1/auth/register',json={'username':username,'password':secrets.token_urlsafe(24),'display_name':'投稿上线验证'})
                check(response.status_code==200,'Disposable registration '+letter)
                a=response.json();accounts.append(a);identities.append({'id':a['account_id'],'username':username})
                (folder/'identities.json').write_text(json.dumps({'accounts':identities}),encoding='utf-8')
            author,other=accounts
            def headers(a):return {'Authorization':'Bearer '+a['access_token']}
            def rpc(a,action,payload):return client.post('/v1/rpc',headers=headers(a),json={'version':1,'action':action,'payload':payload})
            config=rpc(author,'submission_config',{}).json()
            check(config.get('ok') and config.get('categories'),'Authenticated submission configuration')
            check(rpc(author,'profile',{}).status_code==200,'Existing profile RPC remains available')
            comments=client.post('/v1/comments/query',json={'action':'comment_list','payload':{'target_type':'bank','target_id':'marxism','limit':1}})
            check(comments.status_code==200 and comments.json().get('ok'),'Existing anonymous bank discussion remains available')
            image=Image.frombytes('RGB',(512,512),os.urandom(512*512*3));blob=io.BytesIO();image.save(blob,format='PNG')
            asset=uid();raw=blob.getvalue()
            check(len(raw)>256*1024,'Upload fixture exercises the former 256 KB proxy limit')
            upload=client.post('/v1/submission-assets',headers=headers(author),json={'asset_id':asset,'name':'deployment-check.png','data':base64.b64encode(raw).decode()})
            check(upload.status_code==200 and upload.json().get('ok'),'Real PNG upload through HTTPS proxy')
            check(client.get('/v1/submission-assets/'+asset,headers=headers(author)).content==raw,'Author can retrieve the exact private image')
            check(client.get('/v1/submission-assets/'+asset).status_code==404,'Anonymous reader cannot access draft images')
            check(client.get('/v1/submission-assets/'+asset,headers=headers(other)).status_code==404,'Other account cannot access draft images')
            data={'title':'投稿部署验证（临时草稿）','category_id':config['categories'][0]['id'],'course':'','tags':[],'cover_asset_id':asset,'sources':'上线验证后删除，不发表。',
                  'document':{'type':'doc','content':[{'type':'paragraph','content':[{'type':'text','text':'中文草稿保存与权限验证。'}]}]}}
            created=rpc(author,'submission_create',{'client_key':uid(),'operation_id':uid(),'data':data})
            check(created.status_code==200,'Author creates a persistent draft');item=created.json()['submission']
            saved_payload={'submission_id':item['id'],'expected_revision':item['revision'],'operation_id':uid(),'data':{**data,'title':'投稿部署验证（已修改）'}}
            saved=rpc(author,'submission_save',saved_payload);check(saved.status_code==200,'Author saves a new revision')
            check(rpc(author,'submission_save',saved_payload).json()==saved.json(),'Same save operation replays idempotently')
            check(rpc(author,'submission_save',{**saved_payload,'operation_id':uid()}).status_code==409,'Stale revision cannot overwrite a newer draft')
            item=saved.json()['submission']
            check(rpc(other,'submission_get',{'submission_id':item['id']}).status_code==404,'Other account cannot read the draft')
            check(rpc(other,'submission_save',{**saved_payload,'operation_id':uid(),'expected_revision':item['revision']}).status_code==404,'Other account cannot modify the draft')
            check(rpc(author,'submission_mine',{}).json()['counts']['draft']==1,'Author listing and server counts')
            check(rpc(other,'submission_mine',{}).json()['total']==0,'Other account listing is isolated')
            pending=rpc(author,'submission_submit',{'submission_id':item['id'],'expected_revision':item['revision'],'operation_id':uid()})
            check(pending.status_code==200 and pending.json()['submission']['state']=='pending','Submission becomes pending, not published')
            item=pending.json()['submission'];check(item['reward'] is None,'Submission does not create a reward')
            check(client.get('/v1/articles/'+item['id']).status_code==404,'Pending manuscript is not publicly readable')
            denied=rpc(author,'publication_review',{'submission_id':item['id'],'expected_revision':item['revision'],'operation_id':uid(),'decision':'approve'})
            check(denied.status_code==403,'Ordinary author cannot approve a manuscript')
            check(client.get('/v1/articles').status_code==200,'Published article list is available')
            withdrawn=rpc(author,'submission_withdraw',{'submission_id':item['id'],'expected_revision':item['revision'],'operation_id':uid()})
            check(withdrawn.status_code==200 and withdrawn.json()['submission']['state']=='draft','Author can withdraw a pending submission')
            check(client.post('/v1/submission-assets',json={}).status_code==401,'Unauthenticated upload is rejected')
    finally:
        if identities:
            cleanup=subprocess.run(ssh,input=json.dumps({'accounts':identities}),capture_output=True,text=True,timeout=30)
            if cleanup.returncode:raise RuntimeError('Temporary account cleanup failed; see '+str(folder))
            check(json.loads(cleanup.stdout).get('ok') is True,'Exact temporary accounts and private submissions removed')
        report={'passed':len(passed),'checks':passed,'published_test_articles':0,'issued_test_credits':0}
        (folder/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False));print('Evidence:',folder/'result.json')

if __name__=='__main__':main()
