import hashlib
import json
import logging
import os
import secrets
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from typing import Annotated

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from fastapi import Depends, FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, Response
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, ConfigDict, Field
from psycopg import errors
from psycopg.types.json import Jsonb

from database import pool, migrate, transaction, one, lock_users
from domain import DomainError, require, uid, string, dispatch, conversation, profile_view

log = logging.getLogger('hegong')
hasher = PasswordHasher(time_cost=2, memory_cost=32768, parallelism=1)
dummy_hash = hasher.hash(secrets.token_urlsafe(24))
bearer = HTTPBearer(auto_error=False)
SESSION_DAYS = int(os.environ.get('SESSION_DAYS', '7'))


@asynccontextmanager
async def lifespan(app):
    pool.open(wait=True)
    migrate()
    from quiz_rewards import install as install_quiz_banks
    with transaction() as conn:
        install_quiz_banks(conn)
    yield
    pool.close()


app = FastAPI(title='河工开物后端', version='1.0.0', lifespan=lifespan,
              docs_url=None, redoc_url=None, openapi_url=None)


class StrictModel(BaseModel):
    model_config = ConfigDict(extra='forbid')


class Credentials(StrictModel):
    username: str = Field(min_length=4, max_length=32, pattern=r'^[A-Za-z0-9_]+$')
    password: str = Field(min_length=6)


class Registration(Credentials):
    display_name: str = Field(default='', max_length=40)


class PasswordChange(StrictModel):
    current_password: str = Field(min_length=1)
    new_password: str = Field(min_length=6)


class Rpc(StrictModel):
    version: int = Field(default=1, ge=1, le=1)
    action: str = Field(min_length=1, max_length=40, pattern=r'^[a-z_]+$')
    payload: dict = Field(default_factory=dict)


@app.exception_handler(DomainError)
async def domain_error(request, error):
    if error.code == 'discussion_full':
        from comment_capacity import record_rejection
        try:
            record_rejection(error)
        except Exception:
            log.exception('Could not persist discussion capacity alert')
    return JSONResponse(status_code=error.status, content={
        'ok': False, 'account_id': getattr(request.state, 'actor', ''),
        'code': error.code, 'message': error.message, 'definitive': True,
    }, headers={'Cache-Control': 'no-store'})


@app.exception_handler(RequestValidationError)
async def invalid_request(request, error):
    # Never echo validation inputs: they may contain passwords.
    return JSONResponse(status_code=422, content={'ok': False, 'account_id': getattr(request.state, 'actor', ''),
        'code': 'invalid_request', 'message': '字段格式或长度不符合要求。', 'definitive': True})


@app.middleware('http')
async def response_headers(request, call_next):
    try:
        length = int(request.headers.get('content-length', '0'))
    except ValueError:
        length = 999999
    limit = 16 * 1024 * 1024 if request.url.path == '/v1/comments/write' else 9 * 1024 * 1024 if request.url.path == '/v1/submission-assets' else 1024 * 1024 if request.url.path in {'/v1/rpc','/v1/wallet'} else 256 * 1024
    if length > limit:
        return JSONResponse(status_code=413, content={'ok': False, 'code': 'too_large', 'message': '请求内容过大。'})
    response = await call_next(request)
    response.headers['Cache-Control'] = 'no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    return response


async def bounded_json(request, maximum):
    chunks, size = [], 0
    async for chunk in request.stream():
        size += len(chunk)
        require(size <= maximum, 'too_large', '请求内容过大。', 413)
        chunks.append(chunk)
    try: value = json.loads(b''.join(chunks))
    except (ValueError, UnicodeError): raise DomainError('invalid_request','请求数据格式不正确。',400) from None
    require(isinstance(value,dict),message='请求数据格式不正确。')
    return value


def rate_limit(key, limit, seconds=60):
    # Counters are shared across workers. Failed attempts also commit.
    bucket = hashlib.sha256(key.encode()).hexdigest() + ':' + str(int(datetime.now(timezone.utc).timestamp()) // seconds)
    with transaction() as conn:
        row = one(conn, "INSERT INTO rate_limits(bucket,count,expires_at) VALUES (%s,1,now()+(%s*interval '1 second')) ON CONFLICT(bucket) DO UPDATE SET count=rate_limits.count+1 RETURNING count", (bucket, seconds * 2))
    require(row['count'] <= limit, 'rate_limited', '操作过于频繁，请稍后重试。', 429)


def client_ip(request):
    # Uvicorn trusts forwarding headers only from loopback nginx.
    return request.client.host if request.client else 'unknown'


def verify(password, encoded):
    try:
        return hasher.verify(encoded, password)
    except (VerificationError, InvalidHashError):
        return False


def make_session(conn, user_id):
    token = secrets.token_urlsafe(48)
    expires = datetime.now(timezone.utc) + timedelta(days=SESSION_DAYS)
    conn.execute('INSERT INTO sessions(token_hash,user_id,expires_at) VALUES (%s,%s,%s)',
                 (hashlib.sha256(token.encode()).hexdigest(), user_id, expires))
    return {'access_token': token, 'token_type': 'bearer', 'expires_at': expires.isoformat()}


def authenticate(request: Request, authorization: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)]):
    require(authorization is not None and authorization.scheme.lower() == 'bearer' and len(authorization.credentials) <= 256,
            'unauthenticated', '请先登录。', 401)
    token_hash = hashlib.sha256(authorization.credentials.encode()).hexdigest()
    with transaction() as conn:
        row = one(conn, 'SELECT s.user_id FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=%s AND s.expires_at>now() AND NOT u.disabled', (token_hash,))
    require(row is not None, 'unauthenticated', '登录已失效，请重新登录。', 401)
    request.state.actor = row['user_id']
    request.state.token_hash = token_hash
    return row['user_id']


Actor = Annotated[str, Depends(authenticate)]


def optional_actor(request: Request, authorization: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)]):
    return authenticate(request, authorization) if authorization is not None else None


@app.post('/v1/submission-assets')
async def upload_submission_asset(request: Request, actor: Actor):
    from submission_service import upload
    rate_limit('submission-upload:' + actor, 20)
    payload = await bounded_json(request, 9 * 1024 * 1024)
    with transaction() as conn:
        lock_users(conn,actor)
        check_session_after_lock(conn,actor,request)
        return {'ok':True,'asset':upload(conn,actor,payload)}


@app.get('/v1/submission-assets/{asset_id}')
def read_submission_asset(asset_id: str, actor: Annotated[str | None, Depends(optional_actor)]):
    from submission_service import asset
    with transaction() as conn:
        record = asset(conn,asset_id,actor)
        return Response(content=bytes(record['data']),media_type=record['mime'],headers={'Content-Disposition':'inline','Cache-Control':'no-store'})


@app.get('/v1/articles')
def list_published_articles(cursor: str = ''):
    from submission_service import public_page
    with transaction() as conn: return {'ok':True,**public_page(conn,cursor)}


@app.get('/v1/articles/{article_id}')
def read_published_article(article_id: str, actor: Annotated[str | None, Depends(optional_actor)]):
    from submission_service import public_article
    with transaction() as conn: return {'ok':True,'article':public_article(conn,article_id,actor)}


def check_session_after_lock(conn, actor, request):
    valid = one(conn, 'SELECT user_id FROM sessions WHERE token_hash=%s AND user_id=%s AND expires_at>now()', (request.state.token_hash, actor))
    require(valid is not None, 'unauthenticated', '登录已失效，请重新登录。', 401)


@app.get('/health')
def health():
    with transaction() as conn:
        conn.execute('SELECT 1')
    return {'status': 'ok', 'service': 'hegong-backend', 'version': '1.0.0'}


@app.get('/v1/meta')
def meta():
    return {'ok': True, 'auth': {'password': True, 'wechat': False, 'steam': False},
            'registration': os.environ.get('ALLOW_REGISTRATION', 'true') == 'true',
            'username_rule': '4–32 位英文字母、数字或下划线', 'password_min_length': 6,
            'session_days': SESSION_DAYS}


@app.post('/v1/auth/register')
def register(body: Registration, request: Request):
    require(os.environ.get('ALLOW_REGISTRATION', 'true') == 'true', 'unavailable', '暂未开放注册。', 403)
    rate_limit('register:' + client_ip(request), int(os.environ.get('REGISTER_PER_MINUTE', '30')))
    username = body.username.lower()
    password_hash = hasher.hash(body.password)
    display_name = string(body.display_name, 40) or body.username
    try:
        with transaction() as conn:
            actor = uid()
            public_id = str(secrets.randbelow(9000000000) + 1000000000)
            conn.execute('INSERT INTO users(id,public_id,username,password_hash,profile) VALUES (%s,%s,%s,%s,%s)',
                         (actor, public_id, username, password_hash, Jsonb({'display_name': display_name})))
            conversation(conn, actor, actor, 'system')
            result = {'ok': True, 'account_id': actor, **make_session(conn, actor), **profile_view(conn, actor)}
        return result
    except errors.UniqueViolation:
        raise DomainError('username_taken', '用户名已被使用，请更换后重试。', 409) from None


@app.post('/v1/auth/login')
def login(body: Credentials, request: Request):
    username = body.username.lower()
    rate_limit('login-ip:' + client_ip(request), int(os.environ.get('LOGIN_PER_MINUTE', '180')))
    rate_limit('login-user:' + username, 20, 900)
    with transaction() as conn:
        u = one(conn, 'SELECT id,password_hash,disabled FROM users WHERE username=%s', (username,))
    verified = verify(body.password, u['password_hash'] if u else dummy_hash)
    require(u is not None and verified and not u['disabled'], 'invalid_credentials', '用户名或密码不正确。', 401)
    with transaction() as conn:
        lock_users(conn, u['id'])
        current = one(conn, 'SELECT password_hash,disabled FROM users WHERE id=%s', (u['id'],))
        require(current is not None and not current['disabled'] and current['password_hash'] == u['password_hash'], 'invalid_credentials', '登录信息已变化，请重试。', 401)
        return {'ok': True, 'account_id': u['id'], **make_session(conn, u['id']), **profile_view(conn, u['id'])}


@app.post('/v1/auth/logout')
def logout(request: Request, actor: Actor):
    with transaction() as conn:
        lock_users(conn, actor)
        conn.execute('DELETE FROM sessions WHERE token_hash=%s AND user_id=%s', (request.state.token_hash, actor))
    return {'ok': True, 'account_id': actor}


@app.post('/v1/auth/password')
def password_change(body: PasswordChange, request: Request, actor: Actor):
    rate_limit('password:' + actor, 5, 900)
    new_hash = hasher.hash(body.new_password)
    with transaction() as conn:
        lock_users(conn, actor)
        check_session_after_lock(conn, actor, request)
        old = one(conn, 'SELECT password_hash FROM users WHERE id=%s', (actor,))
        require(verify(body.current_password, old['password_hash']), 'invalid_credentials', '当前密码不正确。', 403)
        conn.execute('UPDATE users SET password_hash=%s WHERE id=%s', (new_hash, actor))
        conn.execute('DELETE FROM sessions WHERE user_id=%s', (actor,))
    return {'ok': True, 'account_id': actor, 'message': '密码已修改，所有设备需要重新登录。'}


@app.post('/v1/rpc')
def rpc(body: Rpc, request: Request, actor: Actor):
    rate_limit('rpc:' + actor, int(os.environ.get('RPC_PER_MINUTE', '240')))
    if body.action.startswith('comment_'):
        rate_limit('comments:' + actor, 60)
        if body.action == 'comment_create': rate_limit('comment-create:' + actor, 8)
    if body.action == 'send_text':
        rate_limit('message:' + actor, 40)
    if body.action in {'request_friend', 'find_user'}:
        rate_limit('social-search:' + actor, 30)
    try:
        with transaction() as conn:
            return dispatch(conn, actor, body.action, body.payload,
                            before_action=lambda: check_session_after_lock(conn, actor, request))
    except (errors.DeadlockDetected, errors.LockNotAvailable, errors.SerializationFailure):
        raise DomainError('busy', '服务正忙，请使用相同操作编号重试。', 409) from None


@app.post('/v1/wallet')
def wallet_rpc(body: Rpc, request: Request, actor: Actor):
    from wallet_service import dispatch as wallet_dispatch
    rate_limit('wallet:' + actor, 120)
    try:
        with transaction() as conn:
            return wallet_dispatch(conn, actor, body.action, body.payload,
                                   before_action=lambda: check_session_after_lock(conn, actor, request))
    except (errors.DeadlockDetected, errors.LockNotAvailable, errors.SerializationFailure):
        raise DomainError('busy', '结算正在处理，请重试原练习。', 409) from None


@app.post('/v1/auth/wechat')
@app.post('/v1/auth/steam')
def external_auth():
    raise DomainError('unavailable', '此平台登录尚未配置，当前请使用账号密码。', 503)


@app.post('/v1/comments/query')
def query_comments(body: Rpc, request: Request, actor: Annotated[str | None, Depends(optional_actor)]):
    from comment_service import dispatch as comment_dispatch, READS
    require(body.action in READS, message='此入口只支持读取讨论。')
    rate_limit('comment-read:' + (actor or client_ip(request)), 120)
    try:
        with transaction() as conn:
            return comment_dispatch(conn, actor, body.action, body.payload,
                                    before_action=(lambda: check_session_after_lock(conn, actor, request)) if actor else None)
    except (errors.DeadlockDetected, errors.LockNotAvailable, errors.SerializationFailure):
        raise DomainError('busy', '服务正忙，请稍后重试。', 409) from None


@app.post('/v1/comments/write')
def write_comment(body: Rpc, request: Request, actor: Actor):
    from comment_service import WRITES
    require(body.action in WRITES, message='此入口仅支持评论操作。')
    return rpc(body, request, actor)
