CREATE TABLE IF NOT EXISTS submission_categories (
 id text PRIMARY KEY, name text NOT NULL, enabled boolean NOT NULL DEFAULT true,
 sort_order integer NOT NULL DEFAULT 0
);
INSERT INTO submission_categories(id,name,sort_order) VALUES
 ('course','课程经验',10),('research','科研教程',20),('learning','学习方法',30)
 ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS publication_reviewers (
 user_id text PRIMARY KEY REFERENCES users ON DELETE CASCADE,
 can_publish boolean NOT NULL DEFAULT false
);
CREATE TABLE IF NOT EXISTS submissions (
 id text PRIMARY KEY, author_id text NOT NULL REFERENCES users ON DELETE CASCADE,
 client_key text NOT NULL, revision bigint NOT NULL DEFAULT 0,
 content_revision bigint NOT NULL DEFAULT 0,
 current_revision_id text, pending_revision_id text,
 state text NOT NULL DEFAULT 'draft' CHECK(state IN ('draft','pending','approved','returned','rejected','published','archived')),
 review_note text NOT NULL DEFAULT '', article_id text,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 submitted_at timestamptz, deleted_at timestamptz,
 UNIQUE(author_id,client_key)
);
CREATE INDEX IF NOT EXISTS submissions_author_updated ON submissions(author_id,updated_at DESC,id);
CREATE TABLE IF NOT EXISTS submission_revisions (
 id text PRIMARY KEY, submission_id text NOT NULL REFERENCES submissions ON DELETE CASCADE,
 number bigint NOT NULL, data jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(submission_id,number)
);
CREATE TABLE IF NOT EXISTS submission_assets (
 id text PRIMARY KEY, owner_id text NOT NULL REFERENCES users ON DELETE CASCADE,
 original_name text NOT NULL, mime text NOT NULL, sha256 text NOT NULL,
 width integer NOT NULL, height integer NOT NULL, data bytea NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), CHECK(octet_length(data)<=6291456)
);
CREATE INDEX IF NOT EXISTS submission_assets_owner ON submission_assets(owner_id,created_at);
CREATE TABLE IF NOT EXISTS submission_revision_assets (
 revision_id text NOT NULL REFERENCES submission_revisions ON DELETE CASCADE,
 asset_id text NOT NULL REFERENCES submission_assets ON DELETE RESTRICT,
 PRIMARY KEY(revision_id,asset_id)
);
CREATE TABLE IF NOT EXISTS published_articles (
 id text PRIMARY KEY, submission_id text NOT NULL UNIQUE REFERENCES submissions ON DELETE CASCADE,
 published_revision_id text NOT NULL REFERENCES submission_revisions ON DELETE RESTRICT,
 visible boolean NOT NULL DEFAULT true, views bigint NOT NULL DEFAULT 0,
 first_published_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS published_articles_visible ON published_articles(visible,first_published_at DESC,id);
CREATE TABLE IF NOT EXISTS publication_reviews (
 id text PRIMARY KEY, submission_id text NOT NULL REFERENCES submissions ON DELETE CASCADE,
 revision_id text NOT NULL REFERENCES submission_revisions ON DELETE RESTRICT,
 reviewer_id text NOT NULL REFERENCES users ON DELETE RESTRICT,
 action text NOT NULL CHECK(action IN ('approve','request_changes','reject','publish','unpublish')),
 note text NOT NULL DEFAULT '', created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS article_reactions (
 article_id text NOT NULL REFERENCES published_articles ON DELETE CASCADE,
 actor_id text NOT NULL REFERENCES users ON DELETE CASCADE,
 kind text NOT NULL CHECK(kind IN ('like','bookmark')),
 created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(article_id,actor_id,kind)
);
CREATE TABLE IF NOT EXISTS article_views (
 article_id text NOT NULL REFERENCES published_articles ON DELETE CASCADE,
 actor_id text NOT NULL REFERENCES users ON DELETE CASCADE,
 viewed_on date NOT NULL DEFAULT CURRENT_DATE, PRIMARY KEY(article_id,actor_id,viewed_on)
);
CREATE TABLE IF NOT EXISTS article_reports (
 id text PRIMARY KEY, article_id text NOT NULL REFERENCES published_articles ON DELETE CASCADE,
 actor_id text NOT NULL REFERENCES users ON DELETE CASCADE,
 reason text NOT NULL, note text NOT NULL DEFAULT '', created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS publication_reward_events (
 id text PRIMARY KEY, submission_id text NOT NULL UNIQUE REFERENCES submissions ON DELETE CASCADE,
 article_id text NOT NULL REFERENCES published_articles ON DELETE CASCADE,
 author_id text NOT NULL REFERENCES users ON DELETE CASCADE,
 amount bigint CHECK(amount>0), rule_version text NOT NULL,
 state text NOT NULL CHECK(state IN ('unconfigured','queued','delivered')),
 receipt jsonb, attempts integer NOT NULL DEFAULT 0,
 created_at timestamptz NOT NULL DEFAULT now(), delivered_at timestamptz
);
INSERT INTO schema_versions(version) VALUES (2) ON CONFLICT DO NOTHING;
