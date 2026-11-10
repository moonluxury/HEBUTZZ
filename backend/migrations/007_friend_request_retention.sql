-- Expiration is based on creation time for every status and both directions.
CREATE INDEX IF NOT EXISTS friend_requests_expiration ON friend_requests(created_at,id);
CREATE INDEX IF NOT EXISTS friend_request_notifications ON messages(record_id)
    WHERE kind='notification' AND body->>'event'='friend_request';
CREATE INDEX IF NOT EXISTS friend_request_legacy_receipts ON operations(created_at,actor,operation_id)
    WHERE action IN ('request_friend','respond_request')
      AND NOT response @> '{"_friend_receipt":1}'::jsonb;
INSERT INTO schema_versions(version) VALUES (7) ON CONFLICT DO NOTHING;
