-- One authoritative battery ledger, practice receipts, and deferred author commissions.
CREATE TABLE IF NOT EXISTS battery_wallets (
 user_id text PRIMARY KEY REFERENCES users ON DELETE CASCADE,
 balance bigint NOT NULL DEFAULT 0 CHECK(balance BETWEEN 0 AND 9007199254740991),
 revision bigint NOT NULL DEFAULT 0 CHECK(revision>=0),
 commission_fifths integer NOT NULL DEFAULT 0 CHECK(commission_fifths BETWEEN 0 AND 4)
);
CREATE TABLE IF NOT EXISTS battery_ledger (
 id text PRIMARY KEY, user_id text NOT NULL REFERENCES users ON DELETE CASCADE,
 event_key text NOT NULL, source text NOT NULL, delta bigint NOT NULL CHECK(delta<>0),
 reference text NOT NULL, balance_after bigint NOT NULL CHECK(balance_after>=0),
 created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(user_id,event_key)
);
CREATE INDEX IF NOT EXISTS battery_ledger_page ON battery_ledger(user_id,created_at DESC,id DESC);
CREATE TABLE IF NOT EXISTS quiz_bank_versions (
 subject_id text NOT NULL, version text NOT NULL, grading jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(subject_id,version)
);
CREATE TABLE IF NOT EXISTS battery_practices (
 id text PRIMARY KEY, user_id text NOT NULL REFERENCES users ON DELETE CASCADE,
 request_id text NOT NULL, subject_id text NOT NULL, bank_version text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), finished_at timestamptz,
 answer_hash text, receipt jsonb, UNIQUE(user_id,request_id),
 FOREIGN KEY(subject_id,bank_version) REFERENCES quiz_bank_versions(subject_id,version)
);
ALTER TABLE published_articles ADD COLUMN IF NOT EXISTS price_batteries integer NOT NULL DEFAULT 0
 CHECK(price_batteries=0 OR price_batteries BETWEEN 200 AND 500);
CREATE TABLE IF NOT EXISTS article_purchases (
 id text PRIMARY KEY, buyer_id text NOT NULL REFERENCES users ON DELETE CASCADE,
 author_id text NOT NULL REFERENCES users ON DELETE CASCADE,
 article_id text NOT NULL REFERENCES published_articles ON DELETE RESTRICT,
 revision_id text NOT NULL REFERENCES submission_revisions ON DELETE RESTRICT,
 price_batteries integer NOT NULL CHECK(price_batteries BETWEEN 200 AND 500),
 created_at timestamptz NOT NULL DEFAULT now(), commission_settled_at timestamptz,
 UNIQUE(buyer_id,article_id), CHECK(buyer_id<>author_id)
);
CREATE INDEX IF NOT EXISTS article_commissions_due ON article_purchases(created_at,author_id) WHERE commission_settled_at IS NULL;
CREATE TABLE IF NOT EXISTS battery_commission_runs (
 period_end timestamptz PRIMARY KEY, authors integer NOT NULL, batteries bigint NOT NULL,
 completed_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO schema_versions(version) VALUES (5) ON CONFLICT DO NOTHING;
