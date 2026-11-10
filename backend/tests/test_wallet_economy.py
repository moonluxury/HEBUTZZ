"""Authority, batching, publication, purchases, and three-day commission regression."""
from concurrent.futures import ThreadPoolExecutor
import base64
from datetime import timedelta

import pytest

from test_backend import client, empty_database, register, headers, rpc
from test_submissions import DATA, draft, publisher, publish, transition, call, png
from database import transaction, one, lock_users
from domain import uid
from quiz_rewards import banks, correct, tokens, output
from wallet_service import post, balance, settle_commissions, COMMISSION_EPOCH, PERIOD


def wallet(client, account, action, **payload):
    return client.post('/v1/wallet', headers=headers(account), json={'version':1,'action':action,'payload':payload})


def fund(account, amount):
    with transaction() as conn:
        lock_users(conn,account['account_id'])
        post(conn,account['account_id'],'isolated:'+uid(),'opening',amount,'isolated-test')


def sale(client, buyer, article):
    return call(client,buyer,'article_purchase',article_id=article['id'],expected_revision_id=article['revision_id'],expected_price=article['price_batteries'],operation_id=uid())


def make_article(client, price=200):
    author, admin=register(client),register(client);publisher(admin)
    item=publish(client,author,admin,draft(client,author,{**DATA,'price_batteries':price}))
    article=client.get('/v1/articles/'+item['article_id']).json()['article']
    return author,admin,item,article


def test_practice_batches_only_credit_when_finished_and_replay_once(client):
    a,b=register(client),register(client)
    bank=banks()['marxism'];questions=list(bank['grading'].items())[:2]
    request={'request_id':uid(),'subject_id':'marxism','bank_version':bank['version']}
    started=wallet(client,a,'practice_begin',**request).json()
    assert wallet(client,a,'practice_begin',**request).json()==started
    assert wallet(client,a,'balance').json()['balance']==0
    answers=[{'question_id':qid,'selected_keys':q['keys'],'entered_answers':[]} for qid,q in questions]
    payload={'practice_id':started['practice_id'],'answers':answers}
    assert wallet(client,b,'practice_finish',**payload).status_code==404
    assert wallet(client,a,'practice_finish',**payload,correct=True).status_code==400
    with ThreadPoolExecutor(max_workers=4) as pool:
        responses=list(pool.map(lambda _:wallet(client,a,'practice_finish',**payload),range(4)))
    assert all(r.status_code==200 and r.json()==responses[0].json() for r in responses)
    assert responses[0].json()['reward']['amount']==2
    assert wallet(client,a,'balance').json()['balance']==2
    assert len(wallet(client,a,'ledger',filter='income').json()['items'])==1
    assert wallet(client,a,'practice_finish',practice_id=started['practice_id'],answers=[]).status_code==409
    second=wallet(client,a,'practice_begin',**{**request,'request_id':uid()}).json()
    assert wallet(client,a,'practice_finish',practice_id=second['practice_id'],answers=[answers[0],answers[0]]).status_code==400
    assert wallet(client,a,'practice_finish',practice_id=second['practice_id'],answers=[answers[0]]).json()['balance']==3


def test_practice_grade_matches_local_types_without_executing_input(client):
    assert tokens("'a' + value") == tokens('"a"+value')
    assert tokens("'a'",'cpp') != tokens('"a"','cpp')
    assert output(' 6  2\r\n 3 ')=='6 2\n3'
    assert output('62')!=output('6 2')
    a=register(client)
    for subject in ['python','cpp']:
        bank=banks()[subject]
        for kind in ['fill','output']:
            qid,q=next((qid,q) for qid,q in bank['grading'].items() if q.get('type')==kind)
            answers=[blank['answers'][0] for blank in q['blanks']] if kind=='fill' else [q['answers'][0]]
            answer={'question_id':qid,'selected_keys':[],'entered_answers':answers}
            practice=wallet(client,a,'practice_begin',request_id=uid(),subject_id=subject,bank_version=bank['version']).json()['practice_id']
            assert wallet(client,a,'practice_finish',practice_id=practice,answers=[answer]).json()['reward']['amount']==1
    assert wallet(client,a,'practice_begin',request_id=uid(),subject_id='python',bank_version='wrong').status_code==409


@pytest.mark.parametrize('price',[0,200,201,500])
def test_price_is_part_of_immutable_reviewed_revision(client,price):
    author,admin,item,article=make_article(client,price)
    assert article['price_batteries']==price
    assert article['can_read']==(price==0)
    assert ('document' in article['data'])==(price==0)
    assert wallet(client,author,'balance').json()['balance']==50
    revision=transition(client,author,item,'submission_revise')
    transition(client,author,revision,'submission_save',data={**DATA,'price_batteries':0})
    assert client.get('/v1/articles/'+article['id']).json()['article']['price_batteries']==price


@pytest.mark.parametrize('price',[-1,1,199,501,200.5,'200',True])
def test_invalid_prices_are_rejected(client,price):
    a=register(client)
    assert call(client,a,'submission_create',client_key=uid(),data={**DATA,'price_batteries':price}).status_code==400


def test_paid_content_purchase_is_atomic_and_does_not_credit_author_early(client):
    author,admin,item,article=make_article(client,201)
    buyer=register(client)
    assert sale(client,buyer,article).status_code==409
    fund(buyer,500)
    assert sale(client,buyer,{**article,'price_batteries':200}).status_code==409
    with ThreadPoolExecutor(max_workers=3) as pool: results=list(pool.map(lambda _:sale(client,buyer,article),range(3)))
    assert all(r.status_code==200 and r.json()['article']['can_read'] for r in results)
    assert wallet(client,buyer,'balance').json()['balance']==299
    assert wallet(client,author,'balance').json()['balance']==50
    assert 'document' not in client.get('/v1/articles/'+article['id']).json()['article']['data']
    assert rpc(client,buyer,'article_get',article_id=article['id']).json()['article']['data']['document']==DATA['document']
    assert 'document' not in client.get('/v1/articles').json()['items'][0]['data']
    assert wallet(client,buyer,'ledger',filter='expense').json()['items'][0]['delta']==-201
    with transaction() as conn: assert one(conn,'SELECT count(*) n FROM article_purchases')['n']==1


def test_commission_is_settled_every_three_days_with_fraction_carry(client):
    author,admin,item,article=make_article(client,201)
    buyer=register(client);fund(buyer,500);assert sale(client,buyer,article).status_code==200
    with transaction() as conn:
        conn.execute('UPDATE article_purchases SET created_at=%s',(COMMISSION_EPOCH+timedelta(hours=1),))
        assert settle_commissions(conn,COMMISSION_EPOCH+timedelta(days=2))['batteries']==0
        assert balance(conn,author['account_id'])['balance']==50
    with transaction() as conn:
        assert settle_commissions(conn,COMMISSION_EPOCH+PERIOD)['batteries']==40
        assert balance(conn,author['account_id'])['balance']==90
    with transaction() as conn: assert settle_commissions(conn,COMMISSION_EPOCH+PERIOD)['already_settled']
    revision=transition(client,author,item,'submission_revise')
    revision=transition(client,author,revision,'submission_save',data={**DATA,'price_batteries':204})
    item=publish(client,author,admin,revision)
    article=client.get('/v1/articles/'+item['article_id']).json()['article']
    buyer2=register(client);fund(buyer2,500);assert sale(client,buyer2,article).status_code==200
    with transaction() as conn:
        conn.execute('UPDATE article_purchases SET created_at=%s WHERE buyer_id=%s',(COMMISSION_EPOCH+PERIOD+timedelta(hours=1),buyer2['account_id']))
        assert settle_commissions(conn,COMMISSION_EPOCH+PERIOD*2)['batteries']==41
        assert balance(conn,author['account_id'])['balance']==131
        assert one(conn,'SELECT commission_fifths FROM battery_wallets WHERE user_id=%s',(author['account_id'],))['commission_fifths']==0
        assert one(conn,"SELECT count(*) n FROM battery_ledger WHERE user_id=%s AND source='publication'",(author['account_id'],))['n']==1


def test_paid_body_images_require_purchase_but_cover_is_public(client):
    author,buyer,admin=register(client),register(client),register(client);publisher(admin)
    cover,body=uid(),uid()
    for image in [cover,body]:
        assert client.post('/v1/submission-assets',headers=headers(author),json={'asset_id':image,'name':'test.png','data':base64.b64encode(png()).decode()}).status_code==200
    document={'type':'doc','content':[{'type':'paragraph','content':[{'type':'text','text':'paid image'}]},{'type':'image','attrs':{'asset_id':body,'width':720,'alt':'private'}}]}
    item=publish(client,author,admin,draft(client,author,{**DATA,'price_batteries':200,'cover_asset_id':cover,'document':document}))
    assert client.get('/v1/submission-assets/'+cover).status_code==200
    assert client.get('/v1/submission-assets/'+body).status_code==404
    assert client.get('/v1/submission-assets/'+body,headers=headers(buyer)).status_code==404
    fund(buyer,200)
    article=client.get('/v1/articles/'+item['article_id']).json()['article']
    assert sale(client,buyer,article).status_code==200
    assert client.get('/v1/submission-assets/'+body,headers=headers(buyer)).status_code==200
    assert client.get('/v1/submission-assets/'+body).status_code==404
