"""Delivery adapter for an existing wallet authority; never fabricates a balance.

The receiving wallet must persist the Idempotency-Key and atomically post one
credit before returning persisted=true, the original event/account/amount and a
receipt_id. Retries keep the same event key. Missing configuration leaves queued
events untouched. Production must supply HTTPS and an operator-managed secret.
"""
import os
from urllib.parse import urlsplit

import httpx
from psycopg.types.json import Jsonb

from database import transaction, one


def deliver_one(client=None):
    url = os.environ.get('PUBLICATION_WALLET_URL','')
    key = os.environ.get('PUBLICATION_WALLET_KEY','')
    if not url or not key: return False
    parsed = urlsplit(url)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError('Publication wallet delivery requires a configured HTTPS URL')
    with transaction() as conn:
        event = one(conn,"SELECT * FROM publication_reward_events WHERE state='queued' ORDER BY created_at,id FOR UPDATE SKIP LOCKED LIMIT 1")
        if event is None: return False
        conn.execute('UPDATE publication_reward_events SET attempts=attempts+1 WHERE id=%s',(event['id'],))
        request={'event_id':event['id'],'account_id':event['author_id'],'article_id':event['article_id'],'amount':event['amount'],'rule_version':event['rule_version'],'source':'publication'}
        try:
            if client is None:
                with httpx.Client(timeout=8,follow_redirects=False) as transport:
                    response=transport.post(url,json=request,headers={'Authorization':'Bearer '+key,'Idempotency-Key':event['id']})
            else: response=client.post(url,json=request,headers={'Authorization':'Bearer '+key,'Idempotency-Key':event['id']})
            receipt=response.json() if response.status_code==200 else {}
        except (httpx.HTTPError,ValueError): return False
        valid=(receipt.get('ok') is True and receipt.get('persisted') is True and receipt.get('event_id')==event['id']
               and receipt.get('account_id')==event['author_id'] and receipt.get('amount')==event['amount']
               and isinstance(receipt.get('receipt_id'),str) and 0<len(receipt['receipt_id'])<=160)
        if not valid: return False
        # Store only the proof fields; a wallet response may contain unrelated data.
        safe={name:receipt[name] for name in ['event_id','account_id','amount','receipt_id']}
        conn.execute("UPDATE publication_reward_events SET state='delivered',receipt=%s,delivered_at=now() WHERE id=%s",(Jsonb(safe),event['id']))
    return True
