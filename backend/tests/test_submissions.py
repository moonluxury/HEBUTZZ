import base64
from concurrent.futures import ThreadPoolExecutor
import io
import os

import httpx
from PIL import Image
from test_backend import client, empty_database, register, headers, rpc
from database import transaction, one
from domain import uid
from publication_rewards import deliver_one

DOC={'type':'doc','content':[{'type':'heading','attrs':{'level':1},'content':[{'type':'text','text':'课程基本信息'}]},{'type':'paragraph','content':[{'type':'text','text':'真实中文正文，用于测试稿件保存与审核。','marks':[{'type':'bold'}]}]},{'type':'mathBlock','attrs':{'latex':r'q=-\lambda A\frac{dT}{dx}'}}]}
DATA={'title':'隔离投稿测试','category_id':'course','course':'工程课程','tags':['期末'],'cover_asset_id':'','sources':'测试来源','document':DOC}


def call(client,user,action,**payload):
    if action in {'submission_create','submission_save','submission_submit','submission_withdraw','submission_revise','submission_delete','publication_review','article_react','article_report'}:payload.setdefault('operation_id',uid())
    return rpc(client,user,action,**payload)


def draft(client,user,data=None):
    response=call(client,user,'submission_create',client_key=uid(),data=data or DATA)
    assert response.status_code==200,response.text
    return response.json()['submission']


def transition(client,user,item,action,**extra):
    response=call(client,user,action,submission_id=item['id'],expected_revision=item['revision'],**extra)
    assert response.status_code==200,response.text
    return response.json()['submission']


def publisher(user):
    with transaction() as conn:conn.execute('INSERT INTO publication_reviewers(user_id,can_publish) VALUES (%s,true)',(user['account_id'],))


def publish(client,author,reviewer,item):
    item=transition(client,author,item,'submission_submit')
    item=transition(client,reviewer,item,'publication_review',decision='approve')
    item=transition(client,reviewer,item,'publication_review',decision='publish')
    return item


def png():
    image=Image.new('RGB',(32,24),'#092c87');data=io.BytesIO();image.save(data,format='PNG');return data.getvalue()


def test_author_scope_versions_and_fixed_review_snapshot(client):
    a,b,admin=register(client),register(client),register(client);publisher(admin)
    item=draft(client,a)
    assert call(client,b,'submission_get',submission_id=item['id']).status_code==404
    assert call(client,b,'submission_save',submission_id=item['id'],expected_revision=item['revision'],data=DATA).status_code==404
    assert call(client,a,'publication_review',submission_id=item['id'],expected_revision=item['revision'],decision='publish').status_code==403
    key=uid();payload={'submission_id':item['id'],'expected_revision':item['revision'],'data':{**DATA,'title':'保存后的标题'},'operation_id':key}
    first=call(client,a,'submission_save',**payload);again=call(client,a,'submission_save',**payload)
    assert first.json()==again.json()
    saved=first.json()['submission']
    assert call(client,a,'submission_save',submission_id=item['id'],expected_revision=item['revision'],data=DATA).status_code==409
    pending=transition(client,a,saved,'submission_submit')
    assert pending['state']=='pending'
    assert call(client,a,'submission_save',submission_id=item['id'],expected_revision=pending['revision'],data=DATA).status_code==409
    with transaction() as conn:
        assert one(conn,'SELECT count(*) n FROM publication_reward_events')['n']==0
    approved=transition(client,admin,pending,'publication_review',decision='approve')
    assert client.get('/v1/articles').json()['items']==[]
    with transaction() as conn:assert one(conn,'SELECT count(*) n FROM publication_reward_events')['n']==0
    published=transition(client,admin,approved,'publication_review',decision='publish')
    public=client.get('/v1/articles/'+published['article_id']).json()['article']
    assert public['data']['title']=='保存后的标题' and public['revision_id']==saved['revision_id']
    revision=transition(client,a,published,'submission_revise')
    revision=transition(client,a,revision,'submission_save',data={**DATA,'title':'仍在编辑的新版'})
    assert client.get('/v1/articles/'+published['article_id']).json()['article']['data']['title']=='保存后的标题'
    pending=transition(client,a,revision,'submission_submit')
    returned=transition(client,admin,pending,'publication_review',decision='request_changes',note='补充引用来源')
    assert returned['review_note']=='补充引用来源'
    again=publish(client,a,admin,returned)
    assert again['article_id']==published['article_id']
    assert client.get('/v1/articles/'+again['article_id']).json()['article']['data']['title']=='仍在编辑的新版'


def test_image_permissions_real_mime_and_publication_visibility(client):
    a,b,admin=register(client),register(client),register(client);publisher(admin)
    asset_id=uid();payload={'asset_id':asset_id,'name':'../../note.png','data':base64.b64encode(png()).decode()}
    assert client.post('/v1/submission-assets',headers=headers(a),json=payload).status_code==200
    assert client.get('/v1/submission-assets/'+asset_id).status_code==404
    assert client.get('/v1/submission-assets/'+asset_id,headers=headers(b)).status_code==404
    assert client.get('/v1/submission-assets/'+asset_id,headers=headers(a)).content==png()
    assert call(client,b,'submission_create',client_key=uid(),data={**DATA,'cover_asset_id':asset_id}).status_code==403
    bad={'asset_id':uid(),'name':'looks-like.png','data':base64.b64encode(b'<svg onload="alert(1)"/>').decode()}
    assert client.post('/v1/submission-assets',headers=headers(a),json=bad).status_code==400
    item=draft(client,a,{**DATA,'cover_asset_id':asset_id})
    assert client.get('/v1/submission-assets/'+asset_id).status_code==404
    item=publish(client,a,admin,item)
    assert client.get('/v1/submission-assets/'+asset_id).status_code==200
    item=transition(client,admin,item,'publication_review',decision='unpublish')
    assert client.get('/v1/articles/'+item['article_id']).status_code==404
    assert client.get('/v1/submission-assets/'+asset_id).status_code==404


def test_documents_reject_unsafe_links_and_foreign_attributes(client):
    a=register(client)
    for url in ['javascript:alert(1)','file:///C:/secret','data:text/html,test','https://user:password@example.com']:
        doc={'type':'doc','content':[{'type':'paragraph','content':[{'type':'text','text':'link','marks':[{'type':'link','attrs':{'href':url}}]}]}]}
        assert call(client,a,'submission_create',client_key=uid(),data={**DATA,'document':doc}).status_code==400
    assert call(client,a,'submission_create',client_key=uid(),author_id=uid(),data=DATA).status_code==400
    assert call(client,a,'submission_create',client_key=uid(),data={**DATA,'document':{'type':'doc','content':[{'type':'iframe','attrs':{'src':'file:///secret'}}]}}).status_code==400
    assert call(client,a,'submission_create',client_key=uid(),data={**DATA,'document':{'type':'doc','content':[{'type':'mathBlock','attrs':{'latex':r'\includegraphics{http://internal/}'}}]}}).status_code==400


def test_concurrent_edits_and_reader_actions(client):
    a,b,admin=register(client),register(client),register(client);publisher(admin);item=draft(client,a)
    def save(index):return call(client,a,'submission_save',submission_id=item['id'],expected_revision=item['revision'],data={**DATA,'title':'编辑 '+str(index)}).status_code
    with ThreadPoolExecutor(max_workers=2) as executor:assert sorted(executor.map(save,[1,2]))==[200,409]
    item=call(client,a,'submission_get',submission_id=item['id']).json()['submission'];item=publish(client,a,admin,item)
    for _ in range(2):assert call(client,b,'article_get',article_id=item['article_id']).status_code==200
    assert call(client,b,'article_get',article_id=item['article_id']).json()['article']['views']==1
    for _ in range(2):assert call(client,b,'article_react',article_id=item['article_id'],kind='like',value=True).status_code==200
    assert client.get('/v1/articles/'+item['article_id']).json()['article']['likes']==1
    assert call(client,b,'article_report',article_id=item['article_id'],reason='内容错误',note='请核对推导').status_code==200


def test_rewards_are_after_publication_only_and_idempotent(client,monkeypatch):
    monkeypatch.setenv('PUBLICATION_REWARD_AMOUNT','12')
    a,admin=register(client),register(client);publisher(admin)
    item=publish(client,a,admin,draft(client,a))
    with transaction() as conn:
        event=one(conn,'SELECT * FROM publication_reward_events')
        assert event['state']=='delivered' and event['amount']==50
        assert one(conn,'SELECT balance FROM battery_wallets WHERE user_id=%s',(a['account_id'],))['balance']==50
    assert not deliver_one()
    item=transition(client,a,item,'submission_revise');item=publish(client,a,admin,item)
    with transaction() as conn:
        assert one(conn,'SELECT count(*) n FROM publication_reward_events')['n']==1
        assert one(conn,'SELECT balance FROM battery_wallets WHERE user_id=%s',(a['account_id'],))['balance']==50
        assert one(conn,"SELECT count(*) n FROM battery_ledger WHERE source='publication'")['n']==1
