#!/usr/bin/env bash
set -euo pipefail
test "$(id -u)" = 0
systemctl start hegong-backup.service
archive=$(find /var/backups/hegong -maxdepth 1 -type f -name 'hegong-*.dump' | sort | tail -n 1)
test -n "$archive"
test_db="hegong_restore_$(date -u +%Y%m%d%H%M%S)_test"
runuser -u postgres -- createdb -O hegong "$test_db"
trap 'runuser -u postgres -- dropdb --if-exists "$test_db"' EXIT
runuser -u hegong -- pg_restore --exit-on-error -d "$test_db" < "$archive"
runuser -u hegong -- psql -v ON_ERROR_STOP=1 "$test_db" -c 'SELECT version FROM schema_versions; SELECT count(*) AS restored_users FROM users;'
printf 'BACKUP_RESTORE_OK %s\n' "$archive"
