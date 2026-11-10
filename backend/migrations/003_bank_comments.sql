CREATE TABLE IF NOT EXISTS discussion_banks (
 id text PRIMARY KEY, enabled boolean NOT NULL DEFAULT true, public boolean NOT NULL DEFAULT true
);
INSERT INTO discussion_banks(id) VALUES ('marxism'),('mao'),('xi'),('matlab'),('python'),('cpp') ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS discussion_access (
 bank_id text REFERENCES discussion_banks ON DELETE CASCADE,
 user_id text REFERENCES users ON DELETE CASCADE, PRIMARY KEY(bank_id,user_id)
);
CREATE TABLE IF NOT EXISTS bank_comments (
 id text PRIMARY KEY, bank_id text NOT NULL REFERENCES discussion_banks,
 author_id text NOT NULL REFERENCES users ON DELETE CASCADE,
 parent_id text REFERENCES bank_comments ON DELETE CASCADE,
 body text NOT NULL CHECK(length(body)<=2000),
 status text NOT NULL DEFAULT 'published' CHECK(status IN ('published','pending','hidden','deleted')),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS bank_comments_page ON bank_comments(bank_id,parent_id,status,created_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS bank_comment_replies ON bank_comments(parent_id,status,created_at DESC,id DESC);
CREATE TABLE IF NOT EXISTS bank_comment_likes (
 comment_id text REFERENCES bank_comments ON DELETE CASCADE,
 user_id text REFERENCES users ON DELETE CASCADE, PRIMARY KEY(comment_id,user_id)
);
CREATE TABLE IF NOT EXISTS bank_comment_reports (
 id text PRIMARY KEY, comment_id text NOT NULL REFERENCES bank_comments ON DELETE CASCADE,
 actor_id text NOT NULL REFERENCES users ON DELETE CASCADE, reason text NOT NULL,
 state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','resolved','dismissed')),
 created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(comment_id,actor_id)
);
CREATE INDEX IF NOT EXISTS bank_comment_reports_queue ON bank_comment_reports(state,created_at);
CREATE TABLE IF NOT EXISTS bank_comment_moderators (user_id text PRIMARY KEY REFERENCES users ON DELETE CASCADE);
INSERT INTO schema_versions(version) VALUES (3) ON CONFLICT DO NOTHING;
