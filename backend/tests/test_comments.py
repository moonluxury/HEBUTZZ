"""Actual PostgreSQL authorization, paging, retry and concurrency checks."""
from concurrent.futures import ThreadPoolExecutor
import pytest
from test_backend import client, empty_database, register, headers
from database import transaction, one
from domain import uid, dispatch


def call(client, account, action='comment_list', **values):
    p = {'target_type': 'bank', 'target_id': 'marxism', **values}
    if action not in {'comment_list', 'comment_replies'}: p.setdefault('operation_id', uid())
    path = '/v1/comments/query' if action in {'comment_list','comment_replies'} or not account else '/v1/comments/write'
    return client.post(path,
                       headers=headers(account) if account else {}, json={'version': 1, 'action': action, 'payload': p})


def create(client, account, **values):
    response = call(client, account, 'comment_create', body=values.pop('body', '讨论内容'), **values)
    assert response.status_code == 200, response.text
    return response.json()['comment']


def test_bank_scope_and_anonymous_reads(client):
    a = register(client)
    item = create(client, a)
    assert call(client, None).json()['items'][0]['id'] == item['id']
    assert call(client, None, target_id='python').json()['items'] == []
    assert call(client, None, target_id='question-25').status_code == 404
    assert call(client, None, target_type='article').status_code == 400
    assert call(client, None, 'comment_create', body='no').status_code == 400
    assert call(client, a, 'comment_create', body='x', user_id='forged').status_code == 400
    with transaction() as conn:
        conn.execute("UPDATE discussion_banks SET public=false WHERE id='python'")
    try:
        assert call(client, a, target_id='python').status_code == 403
        assert call(client, None, target_id='python').status_code == 403
        with transaction() as conn: conn.execute("INSERT INTO discussion_access(bank_id,user_id) VALUES ('python',%s)", (a['account_id'],))
        assert call(client, a, target_id='python').status_code == 200
    finally:
        with transaction() as conn: conn.execute("UPDATE discussion_banks SET public=true WHERE id='python'")


def test_retries_and_reply_depth(client):
    a, b = register(client), register(client)
    operation = uid()
    first = create(client, a, operation_id=operation)
    again = create(client, a, operation_id=operation)
    assert first['id'] == again['id']
    assert call(client, a, 'comment_create', body='changed', operation_id=operation).status_code == 409
    reply = create(client, b, parent_id=first['id'])
    assert call(client, b, 'comment_create', body='third level', parent_id=reply['id']).status_code == 409
    assert call(client, b, 'comment_create', body='cross bank', parent_id=first['id'], target_id='python').status_code == 404
    assert call(client, a, 'comment_replies', parent_id=first['id']).json()['items'][0]['id'] == reply['id']
    assert call(client, a).json()['items'][0]['reply_count'] == 1


def test_concurrent_likes_delete_and_reports(client):
    a, b = register(client), register(client)
    item = create(client, a)
    def like(_):
        with transaction() as conn:
            return dispatch(conn, b['account_id'], 'comment_like', {'target_type':'bank','target_id':'marxism','comment_id':item['id'],'value':True,'operation_id':uid()})
    with ThreadPoolExecutor(max_workers=6) as executor:
        result = list(executor.map(like, range(12)))
    assert all(r['comment']['like_count'] == 1 for r in result)
    assert call(client, b, 'comment_like', comment_id=item['id'], value=False).json()['comment']['like_count'] == 0
    assert call(client, b, 'comment_delete', comment_id=item['id']).status_code == 403
    for _ in range(2): assert call(client, b, 'comment_report', comment_id=item['id'], reason='spam').status_code == 200
    with transaction() as conn: assert one(conn, 'SELECT count(*) n FROM bank_comment_reports')['n'] == 1
    assert call(client, a, 'comment_delete', comment_id=item['id']).json()['comment']['status'] == 'deleted'
    assert call(client, None).json()['items'][0]['body'] == ''
    assert call(client, b, 'comment_like', comment_id=item['id'], value=True).status_code == 409


def test_pagination_and_hot_order(client):
    a = register(client)
    with transaction() as conn:
        for i in range(25):
            conn.execute("INSERT INTO bank_comments(id,bank_id,author_id,body,created_at) VALUES (%s,'marxism',%s,%s,now()+(%s*interval '1 second'))", (uid(), a['account_id'], str(i), i))
    first = call(client, a).json()
    assert len(first['items']) == 20 and first['cursor']
    second = call(client, a, cursor=first['cursor']).json()
    assert len(second['items']) == 5 and not second['cursor']
    assert not {x['id'] for x in first['items']} & {x['id'] for x in second['items']}
    assert call(client, a, target_id='python', cursor=first['cursor']).status_code == 400
    assert call(client, None, cursor=first['cursor']).status_code == 400
    assert call(client, a, sort='created_at;DROP TABLE users').status_code == 400
    assert call(client, a, limit=10000).status_code == 400
    oldest = second['items'][-1]
    call(client, a, 'comment_like', comment_id=oldest['id'], value=True)
    assert call(client, a, sort='hot').json()['items'][0]['id'] == oldest['id']


def test_moderation_validation_and_rate_limit(client, monkeypatch):
    a, b = register(client), register(client)
    for body in ['', ' ' * 10, ['invalid'], 'hello\x00', 'hello\x01']:
        assert call(client, a, 'comment_create', body=body).status_code == 400
    monkeypatch.setenv('BANK_COMMENTS_REVIEW_REQUIRED', '1')
    item = create(client, a)
    assert item['status'] == 'pending'
    assert call(client, None).json()['items'] == []
    assert len(call(client, a).json()['items']) == 1
    assert call(client, b, 'comment_moderate', comment_id=item['id'], decision='published').status_code == 403
    with transaction() as conn: conn.execute('INSERT INTO bank_comment_moderators(user_id) VALUES (%s)', (b['account_id'],))
    assert call(client, b, 'comment_moderate', comment_id=item['id'], decision='published').status_code == 200
    assert call(client, None).json()['items'][0]['body'] == '讨论内容'
    assert call(client, b, 'comment_moderate', comment_id=item['id'], decision='hidden').status_code == 200
    assert call(client, None).json()['items'][0]['body'] == ''
    assert call(client, a, 'comment_create', body='one').status_code == 200
    assert call(client, a, 'comment_create', body='two').status_code == 200
    assert call(client, a, 'comment_create', body='rate limited').status_code == 429


@pytest.mark.parametrize('values', [
    {'sort': []}, {'sort': {}}, {'sort': None}, {'limit': True}, {'limit': '20'},
    {'cursor': ['invalid']}, {'cursor': 'tampered'}, {'body': 'unexpected read field'},
    {'target_id': []}, {'target_type': {'bank': True}},
])
def test_malformed_read_parameters_are_client_errors(client, values):
    assert call(client, None, **values).status_code == 400


def test_malformed_moderation_and_write_fields(client):
    a = register(client)
    item = create(client, a)
    with transaction() as conn: conn.execute('INSERT INTO bank_comment_moderators(user_id) VALUES (%s)', (a['account_id'],))
    assert call(client, a, 'comment_moderate', comment_id=item['id'], decision=[]).status_code == 400
    assert call(client, a, 'comment_like', comment_id=item['id'], value='true').status_code == 400
    assert call(client, a, 'comment_create', body='ignored fields must fail', sort='hot').status_code == 400
    assert call(client, a, 'comment_replies', parent_id=item['id'], sort='hot').status_code == 400


@pytest.fixture(autouse=True)
def clear_capacity_alerts(empty_database):
    with transaction() as conn: conn.execute('TRUNCATE discussion_capacity_alerts')


def test_whole_bank_capacity_replies_retry_and_release(client):
    a, b = register(client), register(client)
    root = create(client, a, body='学'*600_000)
    create(client, a, body='习'*300_000, parent_id=root['id'])
    create(client, b, body='论'*100_000)
    assert call(client, None).json()['can_publish'] is False
    operation = uid()
    for _ in range(2):
        response = call(client, a, 'comment_create', body='再', operation_id=operation)
        assert response.status_code == 409 and response.json()['message'] == ''
    with transaction() as conn:
        assert one(conn, 'SELECT sum(char_length(body)) n FROM bank_comments')['n'] == 1_000_000
        assert one(conn, 'SELECT count(*) n FROM discussion_capacity_alerts WHERE resolved_at IS NULL')['n'] == 1
    assert call(client, a, 'comment_delete', comment_id=root['id']).status_code == 200
    assert call(client, None).json()['can_publish'] is True
    assert call(client, a, 'comment_create', body='再', operation_id=operation).status_code == 200
    with transaction() as conn:
        assert one(conn, 'SELECT sum(char_length(body)) n FROM bank_comments')['n'] == 400_001
        assert one(conn, 'SELECT count(*) n FROM discussion_capacity_alerts WHERE resolved_at IS NULL')['n'] == 0
    # Quotas belong to the bank, not a personal allowance spanning courses.
    create(client, a, body='其他题库仍可参与', target_id='python')


def test_single_million_character_comment_and_legacy_rpc(client):
    a = register(client)
    text = '汉🙂' * 500_000
    item = create(client, a, body=text)
    assert item['body'] == text
    with transaction() as conn:
        assert one(conn, 'SELECT char_length(body) n FROM bank_comments WHERE id=%s', (item['id'],))['n'] == 1_000_000
    legacy = client.post('/v1/rpc', headers=headers(a), json={'version':1,'action':'comment_create','payload':{
        'target_type':'bank','target_id':'python','body':'兼容旧客户端','operation_id':uid()}})
    assert legacy.status_code == 200


def test_concurrent_writers_cannot_overfill_bank(client):
    a, b, c = register(client), register(client), register(client)
    create(client, a, body='字'*999_990)
    def write(account): return call(client, account, 'comment_create', body='并发六个字呀').status_code
    with ThreadPoolExecutor(max_workers=2) as executor: statuses = list(executor.map(write, [b,c]))
    assert sorted(statuses) == [200,409]
    with transaction() as conn: assert one(conn, 'SELECT sum(char_length(body)) n FROM bank_comments')['n'] == 999_996


def test_author_college_is_current_profile_data(client):
    a, b = register(client), register(client)
    def college(account, name):
        response = client.post('/v1/rpc', headers=headers(account), json={'version':1,'action':'save_profile','payload':{'patch':{'college':name},'avatar_card_id':''}})
        assert response.status_code == 200
    college(a, '能源与环境工程学院')
    root = create(client, a)
    assert root['author']['college'] == '能源与环境工程学院'
    college(b, '人工智能与数据科学学院')
    reply = create(client, b, parent_id=root['id'])
    assert reply['author']['college'] == '人工智能与数据科学学院'
    college(a, '机械工程学院')
    assert call(client, None).json()['items'][0]['author']['college'] == '机械工程学院'
    assert call(client, a, 'comment_create', body='伪造资料', college='其他学院').status_code == 400


def test_owner_mail_deduplication_and_missing_configuration(client, monkeypatch):
    from comment_capacity import enqueue, released
    from ops.deliver_comment_alerts import deliver_one
    with transaction() as conn: enqueue(conn, 'marxism', 1_000_000, 1)
    for key in ['COMMENT_SMTP_PASSWORD','COMMENT_SMTP_PASSWORD_FILE']: monkeypatch.delenv(key, raising=False)
    assert deliver_one() is True
    with transaction() as conn:
        row = one(conn, 'SELECT * FROM discussion_capacity_alerts')
        assert row['sent_at'] is None and row['last_error'] == 'mail_not_configured'
        conn.execute('UPDATE discussion_capacity_alerts SET next_attempt_at=now()')
    for key,value in {'COMMENT_ALERT_TO':'owner@example.invalid','COMMENT_SMTP_HOST':'smtp.example.invalid','COMMENT_SMTP_FROM':'test@example.invalid','COMMENT_SMTP_USER':'test','COMMENT_SMTP_PASSWORD':'isolated-test-only'}.items(): monkeypatch.setenv(key,value)
    delivered = []
    def sender(alert, config): delivered.append((alert['id'], config['recipient']))
    assert deliver_one(sender) is True
    with transaction() as conn: enqueue(conn, 'marxism', 1_000_000, 2)
    assert deliver_one(sender) is False
    assert len(delivered) == 1 and delivered[0][1] == 'owner@example.invalid'
    with transaction() as conn: released(conn, 'marxism'); enqueue(conn, 'marxism', 1_000_000, 3)
    assert deliver_one(sender) is True and len(delivered) == 2
