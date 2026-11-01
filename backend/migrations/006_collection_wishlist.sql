-- Independent wishlist revision: collecting/transferring cards never removes wants.
CREATE TABLE IF NOT EXISTS collection_wishlists (
 user_id text PRIMARY KEY REFERENCES users ON DELETE CASCADE,
 revision bigint NOT NULL CHECK(revision > 0),
 card_ids jsonb NOT NULL DEFAULT '[]' CHECK(jsonb_typeof(card_ids) = 'array'),
 updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO schema_versions(version) VALUES (6) ON CONFLICT DO NOTHING;
