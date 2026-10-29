-- Version 1. Applied inside one transaction; PostgreSQL is required.
CREATE TABLE IF NOT EXISTS schema_versions (version integer PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS users (
 id text PRIMARY KEY, public_id text NOT NULL UNIQUE, username text NOT NULL UNIQUE,
 password_hash text NOT NULL, profile jsonb NOT NULL DEFAULT '{}',
 revision bigint NOT NULL DEFAULT 0, requests_read bigint NOT NULL DEFAULT 0,
 created_at timestamptz NOT NULL DEFAULT now(), disabled boolean NOT NULL DEFAULT false
);
CREATE TABLE IF NOT EXISTS sessions (
 token_hash text PRIMARY KEY, user_id text NOT NULL REFERENCES users ON DELETE CASCADE,
 expires_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS sessions_user ON sessions(user_id);
CREATE TABLE IF NOT EXISTS external_identities (
 provider text NOT NULL CHECK(provider IN ('wechat','steam')), subject text NOT NULL,
 user_id text NOT NULL REFERENCES users ON DELETE CASCADE,
 PRIMARY KEY(provider,subject), UNIQUE(provider,user_id)
);
CREATE TABLE IF NOT EXISTS relationships (
 a text NOT NULL REFERENCES users ON DELETE CASCADE, b text NOT NULL REFERENCES users ON DELETE CASCADE,
 friends boolean NOT NULL DEFAULT false, blocked_a boolean NOT NULL DEFAULT false,
 blocked_b boolean NOT NULL DEFAULT false, PRIMARY KEY(a,b), CHECK(a<b)
);
CREATE TABLE IF NOT EXISTS friend_requests (
 id text PRIMARY KEY, seq bigserial UNIQUE, sender text NOT NULL REFERENCES users ON DELETE CASCADE,
 recipient text NOT NULL REFERENCES users ON DELETE CASCADE, note text NOT NULL,
 status text NOT NULL CHECK(status IN ('pending','accepted','ignored','invalidated')),
 created_at timestamptz NOT NULL DEFAULT now(), CHECK(sender<>recipient)
);
CREATE UNIQUE INDEX IF NOT EXISTS one_pending_request ON friend_requests(LEAST(sender,recipient),GREATEST(sender,recipient)) WHERE status='pending';
CREATE INDEX IF NOT EXISTS requests_recipient ON friend_requests(recipient,seq);
CREATE INDEX IF NOT EXISTS requests_sender ON friend_requests(sender,seq);
CREATE TABLE IF NOT EXISTS conversations (
 id text PRIMARY KEY, kind text NOT NULL CHECK(kind IN ('direct','system')),
 a text NOT NULL REFERENCES users ON DELETE CASCADE, b text NOT NULL REFERENCES users ON DELETE CASCADE,
 UNIQUE(kind,a,b), CHECK(a<=b), CHECK((kind='system')=(a=b))
);
CREATE TABLE IF NOT EXISTS conversation_members (
 conversation_id text NOT NULL REFERENCES conversations ON DELETE CASCADE,
 user_id text NOT NULL REFERENCES users ON DELETE CASCADE,
 read_seq bigint NOT NULL DEFAULT 0, PRIMARY KEY(conversation_id,user_id)
);
CREATE TABLE IF NOT EXISTS preferences (
 actor text NOT NULL REFERENCES users ON DELETE CASCADE, peer text NOT NULL REFERENCES users ON DELETE CASCADE,
 remark text NOT NULL DEFAULT '', muted boolean NOT NULL DEFAULT false, PRIMARY KEY(actor,peer)
);
CREATE TABLE IF NOT EXISTS messages (
 id text PRIMARY KEY, seq bigserial UNIQUE, conversation_id text NOT NULL REFERENCES conversations ON DELETE CASCADE,
 sender text REFERENCES users ON DELETE CASCADE, kind text NOT NULL CHECK(kind IN ('text','gift','trade','notification')),
 text text NOT NULL DEFAULT '', record_id text, client_id text, body jsonb NOT NULL DEFAULT '{}',
 created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(sender,client_id)
);
CREATE INDEX IF NOT EXISTS message_history ON messages(conversation_id,seq);
CREATE TABLE IF NOT EXISTS inventory (
 user_id text NOT NULL REFERENCES users ON DELETE CASCADE, card_id text NOT NULL,
 count integer NOT NULL CHECK(count>=0), PRIMARY KEY(user_id,card_id)
);
CREATE TABLE IF NOT EXISTS transfers (
 id text PRIMARY KEY, kind text NOT NULL CHECK(kind IN ('gift','trade')),
 initiator text NOT NULL REFERENCES users ON DELETE CASCADE, recipient text NOT NULL REFERENCES users ON DELETE CASCADE,
 give jsonb NOT NULL, receive jsonb NOT NULL, terms_version integer NOT NULL DEFAULT 1,
 status text NOT NULL CHECK(status IN ('pending','completed','cancelled','rejected','invalidated')),
 revision bigint NOT NULL DEFAULT 1, conversation_id text NOT NULL REFERENCES conversations ON DELETE CASCADE,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(initiator<>recipient)
);
CREATE INDEX IF NOT EXISTS transfers_initiator ON transfers(initiator,created_at,id);
CREATE INDEX IF NOT EXISTS transfers_recipient ON transfers(recipient,created_at,id);
CREATE TABLE IF NOT EXISTS inventory_ledger (
 id bigserial PRIMARY KEY, record_id text NOT NULL REFERENCES transfers ON DELETE CASCADE,
 user_id text NOT NULL REFERENCES users ON DELETE CASCADE, card_id text NOT NULL,
 delta integer NOT NULL, leg text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(record_id,user_id,card_id,leg)
);
CREATE TABLE IF NOT EXISTS outbox (
 event_id text PRIMARY KEY, record_id text NOT NULL REFERENCES transfers ON DELETE CASCADE,
 event text NOT NULL, projected_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS operations (
 actor text NOT NULL REFERENCES users ON DELETE CASCADE, operation_id text NOT NULL,
 action text NOT NULL, request_hash text NOT NULL, response jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(actor,operation_id)
);
CREATE TABLE IF NOT EXISTS reports (
 id text PRIMARY KEY, actor text NOT NULL REFERENCES users ON DELETE CASCADE,
 peer text NOT NULL REFERENCES users ON DELETE CASCADE, reason text NOT NULL, note text NOT NULL,
 message_ids jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS study_saves (
 user_id text NOT NULL REFERENCES users ON DELETE CASCADE, device_id text NOT NULL,
 version bigint NOT NULL, payload jsonb NOT NULL, updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,device_id)
);
CREATE TABLE IF NOT EXISTS rate_limits (
 bucket text PRIMARY KEY, count integer NOT NULL, expires_at timestamptz NOT NULL
);
INSERT INTO schema_versions(version) VALUES (1) ON CONFLICT DO NOTHING;
