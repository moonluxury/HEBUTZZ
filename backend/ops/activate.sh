#!/usr/bin/env bash
set -euo pipefail
test -f /etc/letsencrypt/live/hegong-ip/fullchain.pem
systemctl enable --now hegong-backend
systemctl restart hegong-backend
for attempt in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:8000/health >/dev/null; then break; fi
  sleep 1
done
curl -fsS http://127.0.0.1:8000/health
cat > /etc/nginx/conf.d/hegong-limits.conf <<'NGINX'
limit_req_zone $binary_remote_addr zone=hegong_api:10m rate=100r/s;
limit_req_zone $binary_remote_addr zone=hegong_auth:10m rate=10r/s;
NGINX
cat > /etc/nginx/sites-available/hegong <<'NGINX'
server {
    listen 80 default_server;
    server_name 39.107.44.18;
    server_tokens off;
    location /.well-known/acme-challenge/ { root /var/www/hegong; }
    location = /health { proxy_pass http://127.0.0.1:8000; }
    location / { return 308 https://39.107.44.18$request_uri; }
}
server {
    listen 443 ssl default_server;
    server_name 39.107.44.18;
    server_tokens off;
    ssl_certificate /etc/letsencrypt/live/hegong-ip/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/hegong-ip/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    client_max_body_size 256k;
    client_body_timeout 10s;
    limit_req_status 429;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy no-referrer always;
    location /v1/auth/ {
        limit_req zone=hegong_auth burst=30 nodelay;
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 15s;
    }
    location / {
        limit_req zone=hegong_api burst=200 nodelay;
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 15s;
    }
}
NGINX
nginx -t
systemctl reload nginx
systemctl enable --now hegong-backup.timer
systemctl start hegong-backup.service
systemctl is-active nginx postgresql hegong-backend
systemctl list-timers hegong-cert-renew.timer hegong-backup.timer --no-pager
