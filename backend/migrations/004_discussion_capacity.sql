-- Capacity belongs to the whole bank, including replies and retained moderation
-- records. Existing text is never deleted by this migration.
ALTER TABLE bank_comments DROP CONSTRAINT IF EXISTS bank_comments_body_check;
CREATE TABLE IF NOT EXISTS discussion_capacity_alerts (
 id text PRIMARY KEY,
 bank_id text NOT NULL REFERENCES discussion_banks ON DELETE CASCADE,
 used_chars bigint NOT NULL,
 incoming_chars bigint NOT NULL,
 limit_chars bigint NOT NULL DEFAULT 1000000,
 created_at timestamptz NOT NULL DEFAULT now(),
 last_seen_at timestamptz NOT NULL DEFAULT now(),
 resolved_at timestamptz,
 sent_at timestamptz,
 attempts integer NOT NULL DEFAULT 0,
 next_attempt_at timestamptz NOT NULL DEFAULT now(),
 lease_until timestamptz,
 last_error text NOT NULL DEFAULT ''
);
CREATE UNIQUE INDEX IF NOT EXISTS discussion_capacity_one_open
 ON discussion_capacity_alerts(bank_id) WHERE resolved_at IS NULL;
CREATE INDEX IF NOT EXISTS discussion_capacity_delivery
 ON discussion_capacity_alerts(next_attempt_at) WHERE resolved_at IS NULL AND sent_at IS NULL;
INSERT INTO schema_versions(version) VALUES (4) ON CONFLICT DO NOTHING;
