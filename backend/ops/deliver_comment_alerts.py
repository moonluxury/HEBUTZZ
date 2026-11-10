"""Send owner-only capacity mail from the PostgreSQL outbox; no user messages."""
import logging
import os
from pathlib import Path
import smtplib
import ssl
import sys
from email.message import EmailMessage
from email.utils import formatdate, parseaddr

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from database import pool, transaction, one

log = logging.getLogger('comment-alerts')


def configuration():
    recipient = os.environ.get('COMMENT_ALERT_TO', '')
    sender = os.environ.get('COMMENT_SMTP_FROM', '')
    host = os.environ.get('COMMENT_SMTP_HOST', '')
    username = os.environ.get('COMMENT_SMTP_USER', '')
    password = os.environ.get('COMMENT_SMTP_PASSWORD', '')
    password_path = os.environ.get('COMMENT_SMTP_PASSWORD_FILE', '')
    if password_path: password = Path(password_path).read_text().strip()
    if not all([recipient, sender, host, username, password]): return None
    if any('\n' in value or '\r' in value for value in [recipient, sender, host, username]): return None
    if '@' not in parseaddr(recipient)[1] or '@' not in parseaddr(sender)[1]: return None
    return {'recipient':recipient, 'sender':sender, 'host':host, 'username':username, 'password':password,
            'port':int(os.environ.get('COMMENT_SMTP_PORT','465')), 'tls':os.environ.get('COMMENT_SMTP_TLS','ssl')}


def send(alert, config):
    message = EmailMessage()
    message['From'] = config['sender']; message['To'] = config['recipient']
    message['Subject'] = '河工开物：题库讨论容量告警'
    message['Date'] = formatdate(localtime=False)
    domain = parseaddr(config['sender'])[1].split('@')[-1]
    message['Message-ID'] = f'<discussion-capacity-{alert["id"]}@{domain}>'
    message.set_content(f'题库：{alert["bank_id"]}\n已存正文：{alert["used_chars"]:,} 字\n'
                        f'本次提交：{alert["incoming_chars"]:,} 字\n讨论区总容量：{alert["limit_chars"]:,} 字\n\n'
                        '讨论区已达到总容量，或剩余容量不足以接收本次提交。已有评论未被自动删除。\n'
                        '这是仅发给维护者的告警，普通用户界面没有容量提示；未发布草稿仍保留。\n'
                        '请检查并按需要清理该题库的评论。此邮件不包含用户评论正文、登录凭据或个人资料。\n')
    context = ssl.create_default_context()
    if config['tls'] == 'ssl':
        smtp = smtplib.SMTP_SSL(config['host'], config['port'], timeout=20, context=context)
    elif config['tls'] == 'starttls':
        smtp = smtplib.SMTP(config['host'], config['port'], timeout=20)
        smtp.ehlo(); smtp.starttls(context=context); smtp.ehlo()
    else:
        raise ValueError('TLS is required')
    with smtp:
        smtp.login(config['username'], config['password'])
        smtp.send_message(message)


def deliver_one(sender=send):
    with transaction() as conn:
        alert = one(conn, '''SELECT * FROM discussion_capacity_alerts
            WHERE resolved_at IS NULL AND sent_at IS NULL AND next_attempt_at<=now()
            AND (lease_until IS NULL OR lease_until<now())
            AND bank_id NOT LIKE 'commentcheck_%%'
            ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1''')
        if alert is None: return False
        conn.execute("UPDATE discussion_capacity_alerts SET lease_until=now()+interval '5 minutes',attempts=attempts+1 WHERE id=%s", (alert['id'],))
    error = ''
    try:
        config = configuration()
        if config is None: error = 'mail_not_configured'
        else: sender(alert, config)
    except Exception as failure:
        # Do not persist/log SMTP credentials or server error text.
        error = type(failure).__name__
    with transaction() as conn:
        if error:
            conn.execute("UPDATE discussion_capacity_alerts SET lease_until=NULL,last_error=%s,next_attempt_at=now()+interval '15 minutes' WHERE id=%s", (error,alert['id']))
            log.warning('Capacity mail pending: %s', error)
        else:
            conn.execute("UPDATE discussion_capacity_alerts SET lease_until=NULL,last_error='',sent_at=now() WHERE id=%s", (alert['id'],))
    return True


if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    pool.open(wait=True)
    try:
        for _ in range(10):
            if not deliver_one(): break
    finally: pool.close()
