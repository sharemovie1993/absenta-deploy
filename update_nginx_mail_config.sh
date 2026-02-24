#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

if ! command -v nginx >/dev/null 2>&1; then
  echo "nginx tidak terpasang di server ini. Jalankan deploy_nginx_proxy terlebih dahulu."
  exit 1
fi

MAIL_DOMAIN_DEFAULT="mail.absenta.id"
read -p "Domain untuk panel Mailcow/webmail (default ${MAIL_DOMAIN_DEFAULT}): " MAIL_DOMAIN
MAIL_DOMAIN=${MAIL_DOMAIN:-$MAIL_DOMAIN_DEFAULT}

DEFAULT_CERT_DOMAIN=$(echo "$MAIL_DOMAIN" | sed 's/^mail\.//')
read -p "Base domain sertifikat SSL (default ${DEFAULT_CERT_DOMAIN}): " CERT_DOMAIN
CERT_DOMAIN=${CERT_DOMAIN:-$DEFAULT_CERT_DOMAIN}

MAIL_INTERNAL_HOST_DEFAULT="10.50.0.4"
read -p "Host internal Mailcow (default ${MAIL_INTERNAL_HOST_DEFAULT}): " MAIL_INTERNAL_HOST
MAIL_INTERNAL_HOST=${MAIL_INTERNAL_HOST:-$MAIL_INTERNAL_HOST_DEFAULT}

MAIL_INTERNAL_PORT_DEFAULT="80"
read -p "Port HTTP internal Mailcow (default ${MAIL_INTERNAL_PORT_DEFAULT}): " MAIL_INTERNAL_PORT
MAIL_INTERNAL_PORT=${MAIL_INTERNAL_PORT:-$MAIL_INTERNAL_PORT_DEFAULT}

NGINX_CONF="/etc/nginx/sites-available/mail.absenta.conf"

echo "Menulis konfigurasi Nginx untuk ${MAIL_DOMAIN} -> ${MAIL_INTERNAL_HOST}:${MAIL_INTERNAL_PORT} ..."

cat > "$NGINX_CONF" <<EOF
server {
  listen 80;
  server_name ${MAIL_DOMAIN};

  return 301 https://\$host\$request_uri;
}

server {
  listen 443 ssl http2;
  server_name ${MAIL_DOMAIN};

  ssl_certificate /etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/${CERT_DOMAIN}/privkey.pem;

  location / {
    proxy_pass http://${MAIL_INTERNAL_HOST}:${MAIL_INTERNAL_PORT};
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
  }
}
EOF

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/mail.absenta.conf

echo "Memeriksa konfigurasi Nginx..."
nginx -t

echo "Reload Nginx..."
systemctl reload nginx

echo "Update konfigurasi Nginx untuk mail selesai."

