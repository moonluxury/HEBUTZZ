"""Author-scoped drafts, immutable review versions and published-only articles."""
import base64
import hashlib
import io
import json
import os
import re
from pathlib import PurePath

from PIL import Image, UnidentifiedImageError
from psycopg.types.json import Jsonb

from database import one, rows, lock_users
from domain import DomainError, require, uid, string, integer, cursor_encode, cursor_decode
from submission_document import normalize_document, asset_ids, word_count, InvalidDocument, ASSET_ID

STATES = ['draft', 'pending', 'approved', 'returned', 'rejected', 'published', 'archived']
WRITES = {'submission_create','submission_save','submission_submit','submission_withdraw','submission_revise','submission_delete','article_react','article_report','article_purchase','publication_review'}
MAX_IMAGE_BYTES = 6 * 1024 * 1024
EMPTY = {'title':'', 'category_id':'', 'course':'', 'tags':[], 'cover_asset_id':'', 'sources':'', 'price_batteries':0, 'document':{'type':'doc','content':[{'type':'paragraph','content':[]}]}}


def stamp(value): return value.isoformat() if value else None


def config(conn):
    return {'document_version':1, 'categories':rows(conn, 'SELECT id,name FROM submission_categories WHERE enabled ORDER BY sort_order,id'),
            'limits':{'title':100,'text':50000,'tags':5,'images':9,'image_bytes':MAX_IMAGE_BYTES},
            'reward_configured':True, 'publication_reward':50,
            'pricing':{'free':True,'minimum':200,'maximum':500,'currency':'batteries','commission_percent':20,'settlement_days':3},
            'comments_enabled':False}


def identifier(value):
    require(isinstance(value,str) and ASSET_ID.fullmatch(value), message='记录编号不正确。')
    return value


def reviewer(conn, actor, publish=False):
    role = one(conn,'SELECT can_publish FROM publication_reviewers WHERE user_id=%s',(actor,))
    require(role is not None and (not publish or role['can_publish']), 'forbidden','当前账号没有此审核权限。',403)
    return role


def get_submission(conn, actor, submission_id, review=False, lock=False):
    if review: reviewer(conn,actor)
    row = one(conn,'SELECT * FROM submissions WHERE id=%s AND deleted_at IS NULL'+(' FOR UPDATE' if lock else ''),(identifier(submission_id),))
    require(row is not None and (review or row['author_id']==actor),'not_found','稿件不存在或无权访问。',404)
    return row


def current(conn, item):
    row = one(conn,'SELECT * FROM submission_revisions WHERE id=%s',(item['current_revision_id'],))
    require(row is not None,'invalid_revision','稿件版本暂不可用。',409)
    return row


def serialize(conn, item, include_document=True):
    revision = current(conn,item)
    data = dict(revision['data'])
    if not include_document: data.pop('document',None)
    reward = one(conn,'SELECT state,amount,rule_version FROM publication_reward_events WHERE submission_id=%s',(item['id'],))
    return {'id':item['id'],'client_key':item['client_key'],'revision':item['revision'],'revision_id':revision['id'],
            'state':item['state'],'review_note':item['review_note'],'article_id':item['article_id'],
            'created_at':stamp(item['created_at']),'updated_at':stamp(item['updated_at']),'submitted_at':stamp(item['submitted_at']),
            'data':data,'reward':reward,'word_count':word_count(revision['data']['document'])}


def normalize_data(conn, actor, value):
    require(isinstance(value,dict),message='稿件信息不正确。')
    require(not set(value)-set(EMPTY),message='稿件包含不支持的字段。')
    title=string(value.get('title',''),100)
    category=string(value.get('category_id',''),40)
    course=string(value.get('course',''),120)
    sources=string(value.get('sources',''),3000)
    tags=value.get('tags',[])
    price=integer(value.get('price_batteries',0),0,500)
    require(price==0 or price>=200,message='请选择免费或 200–500 电池的售价。')
    require(isinstance(tags,list) and len(tags)<=5,message='最多添加 5 个标签。')
    tags=list(dict.fromkeys(string(tag,20,False) for tag in tags))
    try: document=normalize_document(value.get('document',EMPTY['document']))
    except InvalidDocument as error: raise DomainError('invalid_document',str(error),400) from None
    cover=value.get('cover_asset_id','')
    require(isinstance(cover,str),message='封面引用不正确。')
    references=asset_ids(document)
    if cover: references.add(identifier(cover))
    require(len(references)<=9,message='每篇稿件最多引用 9 张图片。')
    if references:
        found=rows(conn,'SELECT id FROM submission_assets WHERE id=ANY(%s) AND owner_id=%s',(list(references),actor))
        require(len(found)==len(references),'inaccessible_asset','图片尚未上传或不属于当前作者。',403)
    return {'title':title,'category_id':category,'course':course,'tags':tags,'sources':sources,'cover_asset_id':cover,'price_batteries':price,'document':document},references


def insert_revision(conn, item, data, references):
    revision_id=uid()
    number=item['content_revision']+1
    conn.execute('INSERT INTO submission_revisions(id,submission_id,number,data) VALUES (%s,%s,%s,%s)',(revision_id,item['id'],number,Jsonb(data)))
    for asset in references: conn.execute('INSERT INTO submission_revision_assets(revision_id,asset_id) VALUES (%s,%s)',(revision_id,asset))
    return one(conn,'UPDATE submissions SET current_revision_id=%s,content_revision=%s,revision=revision+1,updated_at=now() WHERE id=%s RETURNING *',(revision_id,number,item['id']))


def expect_revision(item,payload):
    expected=payload.get('expected_revision')
    require(type(expected) is int and expected==item['revision'],'revision_conflict','服务器有更新，请核对后再保存。',409)


def public_article(conn, article_id, actor=None):
    article=one(conn,'SELECT a.*,s.author_id,r.data,u.profile,u.public_id,u.username FROM published_articles a JOIN submissions s ON s.id=a.submission_id JOIN submission_revisions r ON r.id=a.published_revision_id JOIN users u ON u.id=s.author_id WHERE a.id=%s AND a.visible AND NOT u.disabled',(identifier(article_id),))
    require(article is not None,'not_found','文章不存在或尚未公开。',404)
    counts={row['kind']:row['n'] for row in rows(conn,'SELECT kind,count(*) n FROM article_reactions WHERE article_id=%s GROUP BY kind',(article_id,))}
    own={row['kind'] for row in rows(conn,'SELECT kind FROM article_reactions WHERE article_id=%s AND actor_id=%s',(article_id,actor))} if actor else set()
    purchased=bool(actor and one(conn,'SELECT 1 FROM article_purchases WHERE article_id=%s AND buyer_id=%s',(article_id,actor)))
    can_read=article['price_batteries']==0 or actor==article['author_id'] or purchased
    data=dict(article['data'])
    data['price_batteries']=article['price_batteries']
    if not can_read:
        data.pop('document',None)
        data.pop('sources',None)
    return {'id':article['id'],'submission_id':article['submission_id'],'revision_id':article['published_revision_id'],
            'data':data,'price_batteries':article['price_batteries'],'can_read':can_read,'purchased':purchased,
            'author':{'id':article['author_id'],'public_id':article['public_id'],'display_name':article['profile'].get('display_name') or article['username'],'avatar_card_id':article['profile'].get('avatar_card_id','')},
            'published_at':stamp(article['first_published_at']),'updated_at':stamp(article['updated_at']),
            'views':article['views'],'likes':counts.get('like',0),'bookmarks':counts.get('bookmark',0),
            'liked':'like' in own,'bookmarked':'bookmark' in own,'can_edit':actor==article['author_id']}


def public_list(conn, limit=100):
    return _public_metadata(conn,'',[],min(limit,100))


def _public_metadata(conn,where,args,limit):
    # Lists never fetch article bodies or perform three queries per row.
    found=rows(conn,"SELECT a.*,s.author_id,r.data-'document'-'sources' AS data,u.public_id,u.profile,u.username FROM published_articles a JOIN submissions s ON s.id=a.submission_id JOIN users u ON u.id=s.author_id JOIN submission_revisions r ON r.id=a.published_revision_id WHERE a.visible AND NOT u.disabled"+where+' ORDER BY a.first_published_at DESC,a.id DESC LIMIT %s',(*args,limit))
    result=[]
    for item in found:
        data=dict(item['data']);data['price_batteries']=item['price_batteries']
        result.append({'id':item['id'],'submission_id':item['submission_id'],'revision_id':item['published_revision_id'],'data':data,'price_batteries':item['price_batteries'],'can_read':item['price_batteries']==0,
                       'author':{'id':item['author_id'],'public_id':item['public_id'],'display_name':item['profile'].get('display_name') or item['username'],'avatar_card_id':item['profile'].get('avatar_card_id','')},
                       'published_at':stamp(item['first_published_at']),'updated_at':stamp(item['updated_at']),'views':item['views']})
    return result


def public_page(conn, cursor=''):
    args=[];where=''
    if cursor:
        position=cursor_decode(string(cursor,2048),'public','articles')
        require(isinstance(position,list) and len(position)==2)
        where=' AND (a.first_published_at,a.id)<(%s::timestamptz,%s)';args.extend(position)
    found=_public_metadata(conn,where,args,51)
    next_cursor=cursor_encode('public','articles',[found[49]['published_at'],found[49]['id']]) if len(found)>50 else ''
    return {'items':found[:50],'next_cursor':next_cursor}


def asset(conn, asset_id, actor=None):
    value=one(conn,'SELECT * FROM submission_assets WHERE id=%s',(identifier(asset_id),))
    allowed=value is not None and value['owner_id']==actor
    if not allowed and actor:
        allowed=one(conn,'SELECT 1 FROM publication_reviewers WHERE user_id=%s',(actor,)) is not None
    if not allowed:
        allowed=one(conn,"SELECT 1 FROM submission_revision_assets r JOIN published_articles a ON a.published_revision_id=r.revision_id JOIN submission_revisions v ON v.id=r.revision_id JOIN submissions s ON s.id=a.submission_id JOIN users u ON u.id=s.author_id WHERE r.asset_id=%s AND a.visible AND NOT u.disabled AND (a.price_batteries=0 OR v.data->>'cover_asset_id'=%s OR EXISTS(SELECT 1 FROM article_purchases p WHERE p.article_id=a.id AND p.buyer_id=%s)) LIMIT 1",(asset_id,asset_id,actor)) is not None
    require(value is not None and allowed,'not_found','图片不存在或无权访问。',404)
    return value


def upload(conn, actor, payload):
    asset_id=identifier(payload.get('asset_id'))
    original=string(payload.get('name','image'),180,False).replace('\\','/').split('/')[-1]
    encoded=payload.get('data','')
    require(isinstance(encoded,str) and len(encoded)<=MAX_IMAGE_BYTES*4//3+8,message='图片超过 6 MB。')
    try: data=base64.b64decode(encoded,validate=True)
    except (ValueError,TypeError): raise DomainError('invalid_image','图片编码不正确。',400) from None
    require(0<len(data)<=MAX_IMAGE_BYTES,message='图片大小不正确。')
    try:
        image=Image.open(io.BytesIO(data))
        require(image.format in {'JPEG','PNG','WEBP'},message='只支持 JPG、PNG、WEBP 图片。')
        require(image.width<=8192 and image.height<=8192 and image.width*image.height<=20000000,message='图片尺寸超过限制。')
        require(not getattr(image,'is_animated',False),message='只支持静态图片。')
        mime={'JPEG':'image/jpeg','PNG':'image/png','WEBP':'image/webp'}[image.format]
        width,height=image.size
        image.verify()
    except (UnidentifiedImageError,OSError,Image.DecompressionBombError): raise DomainError('invalid_image','图片文件无法识别。',400) from None
    digest=hashlib.sha256(data).hexdigest()
    previous=one(conn,'SELECT owner_id,sha256 FROM submission_assets WHERE id=%s',(asset_id,))
    if previous: require(previous['owner_id']==actor and previous['sha256']==digest,'asset_conflict','图片编号已用于其他内容。',409)
    else:
        count=one(conn,'SELECT count(*) n FROM submission_assets WHERE owner_id=%s AND created_at>now()-interval \'1 day\'',(actor,))['n']
        require(count<100,'rate_limited','今日上传图片数量已达到限制。',429)
        conn.execute('INSERT INTO submission_assets(id,owner_id,original_name,mime,sha256,width,height,data) VALUES (%s,%s,%s,%s,%s,%s,%s,%s)',(asset_id,actor,original,mime,digest,width,height,data))
    return {'id':asset_id,'name':original,'mime':mime,'width':width,'height':height,'bytes':len(data),'sha256':digest}


def dispatch(conn,actor,action,p,before_action=None):
    require(isinstance(p,dict) and not set(p)&{'author_id','user_id','role','status','state','account_id'},message='稿件身份和状态由服务器确定。')
    owners=[actor]
    if action=='publication_review':
        reviewer(conn,actor)
        target=get_submission(conn,actor,p.get('submission_id'),review=True)
        owners.append(target['author_id'])
    elif action=='article_purchase':
        target=one(conn,'SELECT s.author_id FROM published_articles a JOIN submissions s ON s.id=a.submission_id WHERE a.id=%s',(identifier(p.get('article_id')),))
        require(target is not None,'not_found','文章不存在。',404)
        owners.append(target['author_id'])
    lock_users(conn,*owners)
    if before_action: before_action()
    request_hash=hashlib.sha256(json.dumps(p,sort_keys=True,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()
    operation_id=string(p.get('operation_id'),128,False) if action in WRITES else None
    if operation_id:
        previous=one(conn,'SELECT * FROM operations WHERE actor=%s AND operation_id=%s',(actor,operation_id))
        if previous:
            require(previous['action']==action and previous['request_hash']==request_hash,'idempotency_conflict','操作编号与原请求不一致。',409)
            return previous['response']
    result={'ok':True,'account_id':actor,**handle(conn,actor,action,p)}
    if operation_id: conn.execute('INSERT INTO operations(actor,operation_id,action,request_hash,response) VALUES (%s,%s,%s,%s,%s)',(actor,operation_id,action,request_hash,Jsonb(result)))
    return result


def handle(conn,actor,action,p):
    if action=='submission_config': return config(conn)
    if action=='submission_create':
        key=identifier(p.get('client_key'))
        item=one(conn,'SELECT * FROM submissions WHERE author_id=%s AND client_key=%s',(actor,key))
        if item:
            require(item['deleted_at'] is None,'not_found','该草稿已删除。',404)
            return {'submission':serialize(conn,item)}
        item=one(conn,'INSERT INTO submissions(id,author_id,client_key) VALUES (%s,%s,%s) RETURNING *',(uid(),actor,key))
        data,references=normalize_data(conn,actor,p.get('data',EMPTY))
        item=insert_revision(conn,item,data,references)
        return {'submission':serialize(conn,item)}
    if action=='submission_mine':
        args=[actor];where=''
        if p.get('cursor'):
            position=cursor_decode(string(p['cursor'],2048),actor,'submissions')
            require(isinstance(position,list) and len(position)==2)
            where=' AND (updated_at,id)<(%s::timestamptz,%s)';args.extend(position)
        found=rows(conn,'SELECT * FROM submissions WHERE author_id=%s AND deleted_at IS NULL'+where+' ORDER BY updated_at DESC,id DESC LIMIT 51',tuple(args))
        counts={state:0 for state in STATES}
        for row in rows(conn,'SELECT state,count(*) n FROM submissions WHERE author_id=%s AND deleted_at IS NULL GROUP BY state',(actor,)): counts[row['state']]=row['n']
        next_cursor=cursor_encode(actor,'submissions',[stamp(found[49]['updated_at']),found[49]['id']]) if len(found)>50 else ''
        return {'items':[serialize(conn,item,False) for item in found[:50]],'counts':counts,'total':sum(counts.values()),'next_cursor':next_cursor}
    if action=='submission_get': return {'submission':serialize(conn,get_submission(conn,actor,p.get('submission_id')))}
    if action in {'submission_save','submission_submit','submission_withdraw','submission_revise','submission_delete'}:
        item=get_submission(conn,actor,p.get('submission_id'),lock=True)
        expect_revision(item,p)
        if action=='submission_save':
            require(item['state'] in {'draft','returned'},'state_conflict','该版本不可编辑，请先撤回审核或创建修订。',409)
            data,references=normalize_data(conn,actor,p.get('data'))
            item=insert_revision(conn,item,data,references)
        elif action=='submission_submit':
            require(item['state'] in {'draft','returned'},'state_conflict','稿件当前不能提交。',409)
            data=current(conn,item)['data']
            require(bool(data['title']),message='请填写文章标题。')
            require(one(conn,'SELECT 1 FROM submission_categories WHERE id=%s AND enabled',(data['category_id'],)) is not None,message='请选择有效的投稿分类。')
            require(word_count(data['document'])>0 or asset_ids(data['document']),message='请填写正文。')
            item=one(conn,"UPDATE submissions SET state='pending',pending_revision_id=current_revision_id,submitted_at=now(),updated_at=now(),revision=revision+1,review_note='' WHERE id=%s RETURNING *",(item['id'],))
        elif action=='submission_withdraw':
            require(item['state'] in {'pending','approved'},'state_conflict','稿件当前不能撤回。',409)
            item=one(conn,"UPDATE submissions SET state='draft',pending_revision_id=NULL,updated_at=now(),revision=revision+1 WHERE id=%s RETURNING *",(item['id'],))
        elif action=='submission_revise':
            require(item['state'] in {'published','archived'},'state_conflict','稿件当前不能创建修订。',409)
            item=one(conn,"UPDATE submissions SET state='draft',pending_revision_id=NULL,updated_at=now(),revision=revision+1 WHERE id=%s RETURNING *",(item['id'],))
        else:
            require(item['state'] in {'draft','returned','rejected'} and not item['article_id'],'state_conflict','只能删除尚未发表的草稿。',409)
            conn.execute('UPDATE submissions SET deleted_at=now(),revision=revision+1 WHERE id=%s',(item['id'],))
            return {'deleted':item['id']}
        return {'submission':serialize(conn,item)}
    if action=='article_list': return public_page(conn,p.get('cursor',''))
    if action=='article_get':
        article_id=identifier(p.get('article_id'))
        public_article(conn,article_id,actor)
        first=one(conn,'INSERT INTO article_views(article_id,actor_id) VALUES (%s,%s) ON CONFLICT DO NOTHING RETURNING article_id',(article_id,actor))
        if first: conn.execute('UPDATE published_articles SET views=views+1 WHERE id=%s',(article_id,))
        return {'article':public_article(conn,article_id,actor)}
    if action=='article_react':
        article_id=identifier(p.get('article_id')); public_article(conn,article_id,actor)
        kind=p.get('kind'); value=p.get('value')
        require(kind in {'like','bookmark'} and type(value) is bool,message='文章操作不正确。')
        if value: conn.execute('INSERT INTO article_reactions(article_id,actor_id,kind) VALUES (%s,%s,%s) ON CONFLICT DO NOTHING',(article_id,actor,kind))
        else: conn.execute('DELETE FROM article_reactions WHERE article_id=%s AND actor_id=%s AND kind=%s',(article_id,actor,kind))
        return {'article':public_article(conn,article_id,actor)}
    if action=='article_purchase': return purchase(conn,actor,p)
    if action=='article_report':
        article_id=identifier(p.get('article_id')); public_article(conn,article_id,actor)
        reason=string(p.get('reason'),40,False);note=string(p.get('note',''),1000)
        require(reason in {'内容错误','侵权','不当内容','其他'},message='请选择举报原因。')
        report_id=uid();conn.execute('INSERT INTO article_reports(id,article_id,actor_id,reason,note) VALUES (%s,%s,%s,%s,%s)',(report_id,article_id,actor,reason,note))
        return {'report_id':report_id,'message':'举报已记录。'}
    if action=='publication_review': return review(conn,actor,p)
    raise DomainError('unavailable','投稿服务不支持此操作。',404)


def review(conn,actor,p):
    decision=p.get('decision')
    require(decision in {'approve','request_changes','reject','publish','unpublish'},message='审核操作不正确。')
    reviewer(conn,actor,publish=decision in {'publish','unpublish'})
    item=get_submission(conn,actor,p.get('submission_id'),review=True,lock=True)
    expect_revision(item,p)
    note=string(p.get('note',''),2000)
    if decision in {'request_changes','reject'}: require(bool(note),message='请填写审核意见。')
    if decision=='approve':
        require(item['state']=='pending','state_conflict','只能审核当前待审版本。',409)
        next_state='approved'
    elif decision in {'request_changes','reject'}:
        require(item['state'] in {'pending','approved'},'state_conflict','该稿件当前不能退回。',409)
        next_state='returned' if decision=='request_changes' else 'rejected'
    elif decision=='publish':
        require(item['state']=='approved' and item['pending_revision_id'],'state_conflict','只有审核通过的固定版本可以发表。',409)
        approved=one(conn,'SELECT data FROM submission_revisions WHERE id=%s',(item['pending_revision_id'],))
        try: normalize_document(approved['data']['document'])
        except InvalidDocument: raise DomainError('invalid_document','待发表文档未通过安全校验。',400) from None
        article_id=item['article_id'] or uid()
        price=approved['data'].get('price_batteries',0)
        conn.execute('INSERT INTO published_articles(id,submission_id,published_revision_id,price_batteries) VALUES (%s,%s,%s,%s) ON CONFLICT(submission_id) DO UPDATE SET published_revision_id=EXCLUDED.published_revision_id,price_batteries=EXCLUDED.price_batteries,visible=true,updated_at=now()',(article_id,item['id'],item['pending_revision_id'],price))
        from wallet_service import publication
        publication(conn,item,article_id)
        conn.execute('UPDATE submissions SET article_id=%s WHERE id=%s',(article_id,item['id']))
        next_state='published'
    else:
        require(item['article_id'] is not None,'state_conflict','该稿件尚未发表。',409)
        conn.execute('UPDATE published_articles SET visible=false,updated_at=now() WHERE id=%s',(item['article_id'],))
        next_state='archived'
    conn.execute('INSERT INTO publication_reviews(id,submission_id,revision_id,reviewer_id,action,note) VALUES (%s,%s,%s,%s,%s,%s)',(uid(),item['id'],item['pending_revision_id'] or item['current_revision_id'],actor,decision,note))
    item=one(conn,'UPDATE submissions SET state=%s,review_note=%s,updated_at=now(),revision=revision+1 WHERE id=%s RETURNING *',(next_state,note,item['id']))
    return {'submission':serialize(conn,item)}


def purchase(conn,actor,p):
    from wallet_service import post,balance
    require(set(p)=={'article_id','expected_revision_id','expected_price','operation_id'})
    article_id=identifier(p.get('article_id'))
    article=one(conn,'SELECT a.*,s.author_id,u.disabled FROM published_articles a JOIN submissions s ON s.id=a.submission_id JOIN users u ON u.id=s.author_id WHERE a.id=%s FOR UPDATE OF a',(article_id,))
    require(article is not None and article['visible'] and not article['disabled'],'not_found','文章已下架或无法购买。',404)
    previous=one(conn,'SELECT id FROM article_purchases WHERE buyer_id=%s AND article_id=%s',(actor,article_id))
    if previous or actor==article['author_id'] or article['price_batteries']==0:
        return {'article':public_article(conn,article_id,actor),'purchase_id':previous['id'] if previous else '',**balance(conn,actor)}
    price=integer(p.get('expected_price'),200,500)
    require(article['published_revision_id']==p.get('expected_revision_id') and article['price_batteries']==price,'price_changed','文章版本或售价已更新，请刷新后重新确认。',409)
    purchase_id=uid()
    post(conn,actor,'purchase:'+article_id,'spend',-price,article_id)
    conn.execute('INSERT INTO article_purchases(id,buyer_id,author_id,article_id,revision_id,price_batteries) VALUES (%s,%s,%s,%s,%s,%s)',(purchase_id,actor,article['author_id'],article_id,article['published_revision_id'],price))
    return {'article':public_article(conn,article_id,actor),'purchase_id':purchase_id,**balance(conn,actor)}
