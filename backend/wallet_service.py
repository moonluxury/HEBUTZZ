"""Battery transactions, one receipt per practice, and three-day sales settlement."""
from datetime import datetime, timedelta, timezone
import hashlib
import json

from psycopg.types.json import Jsonb

from database import one, rows, lock_users
from domain import require, uid, string, integer, cursor_encode, cursor_decode
import quiz_rewards

MAX_BALANCE = 9007199254740991
PUBLICATION_REWARD = 50
RULE_VERSION = 'battery-20261031-v1'
COMMISSION_EPOCH = datetime(2026, 10, 30, 16, tzinfo=timezone.utc)  # Oct 31 00:00 Asia/Shanghai.
PERIOD = timedelta(days=3)


def balance(conn, actor):
    value = one(conn, 'SELECT balance,revision FROM battery_wallets WHERE user_id=%s', (actor,))
    return value or {'balance': 0, 'revision': 0}


def post(conn, actor, event, source, amount, reference):
    # Callers hold the same users-row lock as profile, purchases and publication.
    previous = one(conn, 'SELECT * FROM battery_ledger WHERE user_id=%s AND event_key=%s', (actor, event))
    if previous:
        require(previous['delta'] == amount and previous['source'] == source and previous['reference'] == reference, 'idempotency_conflict', '奖励记录与原操作不一致。', 409)
        return previous['id']
    require(type(amount) is int and amount != 0 and abs(amount) <= MAX_BALANCE)
    conn.execute('INSERT INTO battery_wallets(user_id) VALUES (%s) ON CONFLICT DO NOTHING', (actor,))
    current = one(conn, 'SELECT balance FROM battery_wallets WHERE user_id=%s FOR UPDATE', (actor,))['balance']
    require(current + amount >= 0, 'insufficient_balance', '电池不足，请先通过答题或投稿获得电池。', 409)
    require(current + amount <= MAX_BALANCE, 'balance_limit', '电池余额超出允许范围。', 409)
    identifier = uid()
    conn.execute('INSERT INTO battery_ledger(id,user_id,event_key,source,delta,reference,balance_after) VALUES (%s,%s,%s,%s,%s,%s,%s)', (identifier, actor, event, source, amount, reference, current + amount))
    conn.execute('UPDATE battery_wallets SET balance=%s,revision=revision+1 WHERE user_id=%s', (current + amount, actor))
    return identifier


def catalog():
    return {'packages': [], 'channels': [], 'recharge_enabled': False, 'preview': False,
            'rules': {'summary': '答对一题得 1 电池，结束练习后统一到账；稿件审核上架得 50 电池，销售提成 20%，每 3 天结算。',
                      'quiz': {'enabled': True, 'trusted_attempts': True, 'practice_batches': True, 'amount': 1, 'repeat_policy': 'once_per_practice_question', 'types': quiz_rewards.TYPES, 'bank_versions': {key: value['version'] for key, value in quiz_rewards.banks().items()}},
                      'publication': {'entry_enabled': True, 'amount': 50, 'commission_percent': 20, 'settlement_days': 3}}}


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()


def practice_begin(conn, actor, payload):
    require(set(payload) == {'request_id', 'subject_id', 'bank_version'})
    request_id = string(payload.get('request_id'), 128, False)
    subject = string(payload.get('subject_id'), 32, False)
    version = string(payload.get('bank_version'), 64, False)
    previous = one(conn, 'SELECT * FROM battery_practices WHERE user_id=%s AND request_id=%s', (actor, request_id))
    if previous:
        require(previous['subject_id'] == subject and previous['bank_version'] == version, 'idempotency_conflict', '练习编号与原请求不一致。', 409)
        return {'practice_id': previous['id']}
    require(one(conn, 'SELECT 1 FROM quiz_bank_versions WHERE subject_id=%s AND version=%s', (subject, version)) is not None, 'bank_changed', '题库版本已更新，请更新客户端后重新练习。', 409)
    identifier = uid()
    conn.execute('INSERT INTO battery_practices(id,user_id,request_id,subject_id,bank_version) VALUES (%s,%s,%s,%s,%s)', (identifier, actor, request_id, subject, version))
    return {'practice_id': identifier}


def practice_finish(conn, actor, payload):
    require(set(payload) == {'practice_id', 'answers'})
    practice = one(conn, 'SELECT * FROM battery_practices WHERE id=%s AND user_id=%s FOR UPDATE', (string(payload.get('practice_id'), 64, False), actor))
    require(practice is not None, 'not_found', '未找到本人的练习记录。', 404)
    answers = payload.get('answers')
    require(isinstance(answers, list) and len(answers) <= 2000)
    keys = set()
    for answer in answers:
        require(isinstance(answer, dict) and set(answer) == {'question_id', 'selected_keys', 'entered_answers'})
        qid = string(answer.get('question_id'), 64, False)
        require(qid not in keys, message='同次练习中的题目不能重复结算。')
        keys.add(qid)
        require(isinstance(answer['selected_keys'], list) and len(answer['selected_keys']) <= 30 and all(isinstance(key, str) and len(key) <= 16 for key in answer['selected_keys']))
        require(len(answer['selected_keys']) == len(set(answer['selected_keys'])))
        require(isinstance(answer['entered_answers'], list) and len(answer['entered_answers']) <= 40 and all(isinstance(value, str) and len(value) <= 4096 for value in answer['entered_answers']))
    answer_hash = digest(answers)
    if practice['receipt']:
        require(practice['answer_hash'] == answer_hash, 'idempotency_conflict', '已结算练习不能更改答案。', 409)
        return practice['receipt']
    grading = one(conn, 'SELECT grading FROM quiz_bank_versions WHERE subject_id=%s AND version=%s', (practice['subject_id'], practice['bank_version']))['grading']
    require(all(answer['question_id'] in grading for answer in answers), 'invalid_question', '练习包含当前题库无法核验的题目。', 400)
    correct = sum(quiz_rewards.correct(grading[answer['question_id']], answer) for answer in answers)
    ledger_id = post(conn, actor, 'practice:' + practice['id'], 'quiz', correct, practice['id']) if correct else ''
    receipt = {'reward': {'status': 'credited' if correct else 'ineligible', 'amount': correct, 'ledger_id': ledger_id}, 'correct_count': correct, 'answered_count': len(answers), **balance(conn, actor)}
    conn.execute('UPDATE battery_practices SET finished_at=now(),answer_hash=%s,receipt=%s WHERE id=%s', (answer_hash, Jsonb(receipt), practice['id']))
    return receipt


def publication(conn, item, article_id):
    event_id = 'publication:' + item['id']
    previous = one(conn, 'SELECT * FROM publication_reward_events WHERE submission_id=%s', (item['id'],))
    if previous and previous['state'] == 'delivered': return
    ledger_id = post(conn, item['author_id'], event_id, 'publication', PUBLICATION_REWARD, article_id)
    receipt = {'event_id': event_id, 'account_id': item['author_id'], 'amount': PUBLICATION_REWARD, 'receipt_id': ledger_id}
    conn.execute("INSERT INTO publication_reward_events(id,submission_id,article_id,author_id,amount,rule_version,state,receipt,delivered_at) VALUES (%s,%s,%s,%s,%s,%s,'delivered',%s,now()) ON CONFLICT(submission_id) DO UPDATE SET amount=EXCLUDED.amount,rule_version=EXCLUDED.rule_version,state='delivered',receipt=EXCLUDED.receipt,delivered_at=now()", (event_id, item['id'], article_id, item['author_id'], PUBLICATION_REWARD, RULE_VERSION, Jsonb(receipt)))


def ledger(conn, actor, payload):
    kind = payload.get('filter', 'all')
    require(kind in {'all', 'income', 'expense'})
    limit = integer(payload.get('limit', 20), 1, 50)
    cursor = string(payload.get('cursor', ''), 2048)
    args = [actor]
    where = ' AND delta>0' if kind == 'income' else ' AND delta<0' if kind == 'expense' else ''
    if cursor:
        point = cursor_decode(cursor, actor, 'battery:' + kind)
        require(isinstance(point, list) and len(point) == 2)
        where += ' AND (created_at,id)<(%s::timestamptz,%s)'
        args.extend(point)
    values = rows(conn, 'SELECT id,user_id,source,delta,reference,created_at FROM battery_ledger WHERE user_id=%s' + where + ' ORDER BY created_at DESC,id DESC LIMIT %s', (*args, limit + 1))
    items = [{'id': value['id'], 'account_id': value['user_id'], 'source': value['source'], 'delta': value['delta'], 'reference': value['reference'], 'created_at': value['created_at'].isoformat()} for value in values[:limit]]
    following = cursor_encode(actor, 'battery:' + kind, [items[-1]['created_at'], items[-1]['id']]) if len(values) > limit else ''
    return {'items': items, 'next_cursor': following}


def dispatch(conn, actor, action, payload, before_action=None):
    require(isinstance(payload, dict))
    require(action in {'balance', 'catalog', 'ledger', 'orders', 'practice_begin', 'practice_finish', 'card_draw_options', 'card_draw', 'card_draw_status'}, 'unavailable', '该电池功能尚未开放。', 404)
    lock_users(conn, actor)
    if before_action: before_action()
    if action in {'card_draw_options', 'card_draw', 'card_draw_status'}:
        from card_draw_service import handle as card_draw
        result = card_draw(conn, actor, action, payload)
    elif action == 'balance': result = balance(conn, actor)
    elif action == 'catalog': result = catalog()
    elif action == 'ledger': result = ledger(conn, actor, payload)
    elif action == 'orders': result = {'items': [], 'next_cursor': ''}
    elif action == 'practice_begin': result = practice_begin(conn, actor, payload)
    else: result = practice_finish(conn, actor, payload)
    return {'ok': True, 'account_id': actor, **result}


def settle_commissions(conn, now=None):
    now = now or datetime.now(timezone.utc)
    if now < COMMISSION_EPOCH + PERIOD: return {'authors': 0, 'batteries': 0}
    end = COMMISSION_EPOCH + ((now - COMMISSION_EPOCH) // PERIOD) * PERIOD
    if not one(conn, 'SELECT pg_try_advisory_xact_lock(72810435) AS acquired')['acquired']:
        return {'busy': True}
    if one(conn, 'SELECT 1 FROM battery_commission_runs WHERE period_end=%s', (end,)):
        return {'authors': 0, 'batteries': 0, 'already_settled': True}
    due = rows(conn, 'SELECT author_id,sum(price_batteries) AS fifths FROM article_purchases WHERE commission_settled_at IS NULL AND created_at<%s GROUP BY author_id ORDER BY author_id', (end,))
    total = 0
    for author in due:
        owner = author['author_id']
        lock_users(conn, owner)
        conn.execute('INSERT INTO battery_wallets(user_id) VALUES (%s) ON CONFLICT DO NOTHING', (owner,))
        remainder = one(conn, 'SELECT commission_fifths FROM battery_wallets WHERE user_id=%s FOR UPDATE', (owner,))['commission_fifths']
        amount, remainder = divmod(int(author['fifths']) + remainder, 5)
        if amount:
            post(conn, owner, 'commission:' + end.isoformat(), 'commission', amount, end.isoformat())
            total += amount
        conn.execute('UPDATE battery_wallets SET commission_fifths=%s WHERE user_id=%s', (remainder, owner))
        conn.execute('UPDATE article_purchases SET commission_settled_at=%s WHERE author_id=%s AND commission_settled_at IS NULL AND created_at<%s', (end, owner, end))
    conn.execute('INSERT INTO battery_commission_runs(period_end,authors,batteries) VALUES (%s,%s,%s)', (end, len(due), total))
    return {'authors': len(due), 'batteries': total, 'period_end': end.isoformat()}
