"""Run the actual backend with disposable accounts in an explicit *_test DB.

The output session file is ignored by Git and is consumed only by isolated Godot
checks. This command refuses production databases and never uses live accounts.
"""
import base64
import json
import os
from pathlib import Path
import secrets
import sys

ROOT=Path(__file__).resolve().parents[1]
os.environ.setdefault('DATABASE_URL','host=127.0.0.1 port=55439 dbname=hegong_submission_test user=hegong_test_owner')
os.environ.setdefault('CURSOR_SECRET','isolated-submission-test-key')
os.environ['REGISTER_PER_MINUTE']='10000';os.environ['RPC_PER_MINUTE']='10000'
sys.path.insert(0,str(ROOT/'backend'))
from psycopg.conninfo import conninfo_to_dict
assert conninfo_to_dict(os.environ['DATABASE_URL']).get('dbname','').endswith('_test')
from fastapi.testclient import TestClient
from app import app
from database import transaction
from domain import uid

def run_seed():
    client=TestClient(app)
    client.__enter__()
    def register(label):
        username='submission_'+secrets.token_hex(5);password=secrets.token_urlsafe(18)
        r=client.post('/v1/auth/register',json={'username':username,'password':password,'display_name':label});r.raise_for_status()
        return r.json()
    author=register('测试投稿作者');reviewer=register('隔离审核员')
    with transaction() as conn:
        conn.execute('INSERT INTO publication_reviewers(user_id,can_publish) VALUES (%s,true)',(reviewer['account_id'],))
        conn.execute('INSERT INTO inventory(user_id,card_id,count) VALUES (%s,%s,2)',(author['account_id'],'0004'))
    def call(who,action,**payload):
        if action not in ['submission_get','submission_config']:payload.setdefault('operation_id',uid())
        r=client.post('/v1/rpc',headers={'Authorization':'Bearer '+who['access_token']},json={'action':action,'payload':payload});r.raise_for_status();return r.json()
    call(author,'save_profile',patch={},avatar_card_id='0004',avatar_change=True)
    from PIL import Image
    image=ROOT/'assets/questionbank/python_v2/choice_001.png'
    for candidate in sorted((ROOT/'assets/questionbank/python_v2').glob('*.png')):
        with Image.open(candidate) as im:
            if im.width>=480 and im.height>=230:image=candidate;break
    asset_id=uid()
    r=client.post('/v1/submission-assets',headers={'Authorization':'Bearer '+author['access_token']},json={'asset_id':asset_id,'name':image.name,'data':base64.b64encode(image.read_bytes()).decode()});r.raise_for_status()
    def text(value):return {'type':'text','text':value}
    def para(value):return {'type':'paragraph','content':[text(value)]}
    def heading(value):return {'type':'heading','attrs':{'level':2},'content':[text(value)]}
    blocks=[heading('一、课程基本信息'),para('传热学是能源与动力工程、过程装备等专业的基础课程，主要研究热量传递的基本机理及其工程应用。期末考试需要理解基本概念、适用条件和计算步骤。'),heading('二、重点内容总结'),para('热传导、对流换热与辐射换热构成复习主线。先理解物理过程，再分析边界条件，最后选择适用公式。'),{'type':'mathBlock','attrs':{'latex':r'q=-\lambda A\frac{dT}{dx}'}},{'type':'orderedList','attrs':{'start':1},'content':[{'type':'listItem','content':[para(s)]} for s in ['热传导的基本定律与一维稳态传热公式的推导及应用','对流换热的基本理论、经验关联式及工程应用','辐射换热的基本概念、斯蒂芬—玻尔兹曼定律','复合传热与换热器的计算方法']]},heading('三、常见题型'),para('常见题型包括选择题、填空题、简答题和计算题。计算前需要检查单位与边界条件。'),{'type':'image','attrs':{'asset_id':asset_id,'width':700,'alt':'隔离验收使用的项目既有学习图片'}},heading('四、复习建议')]
    blocks += [para('以课堂和课程教学大纲为准，结合真实作业与历年练习归纳解题方法。每次计算应写出已知条件、基本方程、代入过程与结果检验。'*2) for _ in range(5)]
    blocks += [heading('五、参考资料'),{'type':'bulletList','content':[{'type':'listItem','content':[para(s)]} for s in ['课程教材及教师提供的学习资料','课堂 PPT 与课后习题','本文用于隔离验证，不作为正式学习资源发布。']]}]
    data={'title':'传热学期末复习经验（含重点总结与例题）','category_id':'course','course':'能源与动力工程','tags':['传热学','期末','复习'],'cover_asset_id':asset_id,'sources':'开发隔离数据；正文和图片仅用于验收。','document':{'type':'doc','content':blocks}}
    draft=call(author,'submission_create',client_key=uid(),data=data)['submission']
    items=[];article_id=None
    for index,(title,status) in enumerate([('传热学期末复习经验（含重点总结与例题）','pending'),('Fluent入门教程：从网格到后处理','published'),('制冷循环常用工质对比与选型建议','returned'),('传热学期末复习经验（含重点总结与例题）','published'),('工程热力学期末重点整理','published'),('课堂笔记与复习方法','pending')]):
        item=call(author,'submission_create',client_key=uid(),data={**data,'title':title})['submission']
        item=call(author,'submission_submit',submission_id=item['id'],expected_revision=item['revision'])['submission']
        if status=='returned':item=call(reviewer,'publication_review',submission_id=item['id'],expected_revision=item['revision'],decision='request_changes',note='请补充工质来源与参考文献。')['submission']
        if status=='published':
            item=call(reviewer,'publication_review',submission_id=item['id'],expected_revision=item['revision'],decision='approve')['submission']
            item=call(reviewer,'publication_review',submission_id=item['id'],expected_revision=item['revision'],decision='publish')['submission']
            if index==3:article_id=item['article_id']
        items.append(item['id'])
    (ROOT/'.godot_appdata/submission-check-session.json').write_text(json.dumps({'account_id':author['account_id'],'access_token':author['access_token'],'draft_id':draft['id'],'article_id':article_id,'image':str(image),'items':items,'initial_data':data}),encoding='utf-8')
    print('Isolated submission accounts and article states prepared',flush=True)
    return client

if __name__=='__main__':
    lifespan_client=run_seed()
    import uvicorn
    uvicorn.run(app,host='127.0.0.1',port=8059,log_level='warning',access_log=False,lifespan='off')
