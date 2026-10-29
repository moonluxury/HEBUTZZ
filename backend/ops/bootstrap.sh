#!/usr/bin/env bash
set -euo pipefail
test "$(id -u)" = 0
install -d -m 755 /var/www/hegong/.well-known/acme-challenge
install -d -m 700 /etc/hegong/tls
if [ ! -f /etc/hegong/tls/bootstrap.key ]; then
  openssl req -x509 -nodes -newkey rsa:3072 -days 30 \
    -keyout /etc/hegong/tls/bootstrap.key -out /etc/hegong/tls/bootstrap.crt \
    -subj '/CN=39.107.44.18' -addext 'subjectAltName=IP:39.107.44.18' >/dev/null 2>&1
  chmod 600 /etc/hegong/tls/bootstrap.key
fi
cat > /etc/nginx/sites-available/hegong <<'NGINX'
server {
    listen 80 default_server;
    server_name 39.107.44.18;
    server_tokens off;
    location /.well-known/acme-challenge/ { root /var/www/hegong; }
    location = /health { default_type application/json; return 200 '{"status":"gateway_ready"}'; }
    location / { return 308 https://39.107.44.18$request_uri; }
}
server {
    listen 443 ssl default_server;
    server_name 39.107.44.18;
    server_tokens off;
    ssl_certificate /etc/hegong/tls/bootstrap.crt;
    ssl_certificate_key /etc/hegong/tls/bootstrap.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    client_max_body_size 256k;
    location = /health { default_type application/json; return 200 '{"status":"gateway_ready"}'; }
    location / { return 503; }
}
NGINX
if [ -L /etc/nginx/sites-enabled/default ]; then
  unlink /etc/nginx/sites-enabled/default
fi
ln -sfn /etc/nginx/sites-available/hegong /etc/nginx/sites-enabled/hegong
nginx -t
systemctl enable --now nginx
systemctl reload nginx
ufw allow 22/tcp comment 'SSH management'
ufw allow 80/tcp comment 'HTTP and certificate validation'
ufw allow 443/tcp comment 'HTTPS API'
ufw --force enable
printf '\nGATEWAY_READY\n'
ss -lntp
ufw status
