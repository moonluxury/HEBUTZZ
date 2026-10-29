#!/usr/bin/env bash
set -euo pipefail
test "$(id -u)" = 0
id hegong >/dev/null 2>&1 || useradd --system --home /opt/hegong --shell /usr/sbin/nologin hegong
install -d -m 755 /opt/hegong
install -d -m 750 -o root -g hegong /etc/hegong
runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='hegong'" | grep -q 1 || runuser -u postgres -- createuser hegong
runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='hegong'" | grep -q 1 || runuser -u postgres -- createdb -O hegong hegong
runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='hegong_test'" | grep -q 1 || runuser -u postgres -- createdb -O hegong hegong_test
if [ ! -f /etc/hegong/backend.env ]; then
  python3 - <<'PY'
import secrets
from pathlib import Path
p = Path('/etc/hegong/backend.env')
p.write_text('DATABASE_URL="dbname=hegong user=hegong host=/var/run/postgresql"\nCURSOR_SECRET=' + secrets.token_hex(32) + '\nCATALOG_PATH=/opt/hegong/backend/collection_catalog.json\nALLOW_REGISTRATION=true\nPYTHONDONTWRITEBYTECODE=1\n', encoding='utf-8')
PY
fi
chown root:hegong /etc/hegong/backend.env
chmod 640 /etc/hegong/backend.env
python3 -m venv /opt/hegong/venv
if [ -f /opt/hegong/backend/requirements.lock ]; then
  /opt/hegong/venv/bin/pip -q install -r /opt/hegong/backend/requirements.lock
else
  /opt/hegong/venv/bin/pip -q install -r /opt/hegong/backend/requirements.txt
  /opt/hegong/venv/bin/pip freeze > /opt/hegong/backend/requirements.lock
fi
cat > /etc/systemd/system/hegong-backend.service <<'UNIT'
[Unit]
Description=Hegong account and social API
After=network.target postgresql.service
Requires=postgresql.service
[Service]
User=hegong
Group=hegong
WorkingDirectory=/opt/hegong/backend
EnvironmentFile=/etc/hegong/backend.env
ExecStart=/opt/hegong/venv/bin/uvicorn app:app --host 127.0.0.1 --port 8000 --workers 2 --proxy-headers --forwarded-allow-ips 127.0.0.1 --no-access-log
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
UMask=0077
LimitNOFILE=16384
[Install]
WantedBy=multi-user.target
UNIT
cat > /etc/systemd/system/hegong-cert-renew.service <<'UNIT'
[Unit]
Description=Renew Hegong short-lived IP TLS certificate
After=network-online.target nginx.service
[Service]
Type=oneshot
ExecStart=/opt/hegong-certbot/bin/certbot renew --quiet --deploy-hook "systemctl reload nginx"
UNIT
cat > /etc/systemd/system/hegong-cert-renew.timer <<'UNIT'
[Unit]
Description=Check short-lived certificates twice daily
[Timer]
OnCalendar=*-*-* 00,12:00:00
RandomizedDelaySec=1800
Persistent=true
[Install]
WantedBy=timers.target
UNIT
install -d -m 700 /var/backups/hegong
cat > /usr/local/sbin/hegong-backup <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
umask 077
target="/var/backups/hegong/hegong-$(date -u +%Y%m%dT%H%M%SZ).dump"
runuser -u hegong -- pg_dump -Fc hegong > "$target.tmp"
pg_restore --list "$target.tmp" >/dev/null
mv "$target.tmp" "$target"
find /var/backups/hegong -maxdepth 1 -type f -name 'hegong-*.dump' -mtime +7 -delete
runuser -u hegong -- psql hegong -q -c 'DELETE FROM sessions WHERE expires_at < now(); DELETE FROM rate_limits WHERE expires_at < now();'
SCRIPT
chmod 700 /usr/local/sbin/hegong-backup
cat > /etc/systemd/system/hegong-backup.service <<'UNIT'
[Unit]
Description=Back up Hegong PostgreSQL database
After=postgresql.service
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/hegong-backup
UNIT
cat > /etc/systemd/system/hegong-backup.timer <<'UNIT'
[Unit]
Description=Daily Hegong database backup
[Timer]
OnCalendar=*-*-* 19:00:00 UTC
RandomizedDelaySec=600
Persistent=true
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now hegong-cert-renew.timer
printf 'INSTALL_READY\n'
