#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

if ! command -v nginx >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y && apt-get install -y nginx
  elif command -v apt >/dev/null 2>&1; then
    apt update -y && apt install -y nginx
  else
    echo "Package manager tidak terdeteksi. Install nginx manual."
    exit 1
  fi
fi

read -p "Domain/server_name (contoh app.absenta.id): " VH_DOMAIN
if [ -z "$VH_DOMAIN" ]; then
  echo "Domain wajib diisi."
  exit 1
fi

echo "Mode Virtual Host:"
echo "1) Reverse Proxy ke upstream"
echo "2) Static site (document root)"
read -p "Pilih mode (1/2, default 1): " VH_MODE
VH_MODE=${VH_MODE:-1}

CONF_DIR="/etc/nginx/sites-available"
ENABLED_DIR="/etc/nginx/sites-enabled"
mkdir -p "$CONF_DIR" "$ENABLED_DIR" || true
CONF_PATH="$CONF_DIR/${VH_DOMAIN}.conf"

if [ "$VH_MODE" = "2" ]; then
  read -p "Document root (default /var/www/${VH_DOMAIN}/html): " DOC_ROOT
  DOC_ROOT=${DOC_ROOT:-/var/www/${VH_DOMAIN}/html}
  mkdir -p "$DOC_ROOT"
  if [ ! -f "${DOC_ROOT}/index.html" ]; then
    cat > "${DOC_ROOT}/index.html" <<EOF
<!doctype html><html><head><meta charset="utf-8"><title>${VH_DOMAIN}</title></head><body><h1>${VH_DOMAIN}</h1><p>Nginx vhost aktif.</p></body></html>
EOF
  fi
  cat > "$CONF_PATH" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${VH_DOMAIN};
    root ${DOC_ROOT};
    index index.html index.htm;
    access_log /var/log/nginx/${VH_DOMAIN}_access.log;
    error_log  /var/log/nginx/${VH_DOMAIN}_error.log;
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
else
  read -p "Upstream host (default 127.0.0.1): " UP_HOST
  UP_HOST=${UP_HOST:-127.0.0.1}
  read -p "Upstream port (default 3000): " UP_PORT
  UP_PORT=${UP_PORT:-3000}
  cat > "$CONF_PATH" <<EOF
upstream ${VH_DOMAIN//[^a-zA-Z0-9_]/_}_up {
    server ${UP_HOST}:${UP_PORT};
    keepalive 16;
}
server {
    listen 80;
    listen [::]:80;
    server_name ${VH_DOMAIN};
    access_log /var/log/nginx/${VH_DOMAIN}_access.log;
    error_log  /var/log/nginx/${VH_DOMAIN}_error.log;
    location / {
        proxy_pass http://${VH_DOMAIN//[^a-zA-Z0-9_]/_}_up;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
}
EOF
fi

ln -sf "$CONF_PATH" "$ENABLED_DIR/${VH_DOMAIN}.conf"

if command -v ufw >/dev/null 2>&1; then
  ufw allow 'Nginx Full' || { ufw allow 80/tcp || true; ufw allow 443/tcp || true; }
elif command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-service=http || firewall-cmd --permanent --add-port=80/tcp || true
  firewall-cmd --permanent --add-service=https || firewall-cmd --permanent --add-port=443/tcp || true
  firewall-cmd --reload || true
fi

nginx -t
systemctl enable nginx
systemctl reload nginx || systemctl restart nginx

read -p "Pasang SSL Let's Encrypt sekarang untuk ${VH_DOMAIN}? (y/n, default n): " INSTALL_SSL
INSTALL_SSL=${INSTALL_SSL:-n}
if [ "$INSTALL_SSL" = "y" ] || [ "$INSTALL_SSL" = "Y" ]; then
  if ! command -v certbot >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -y && apt-get install -y certbot python3-certbot-nginx || true
    elif command -v apt >/dev/null 2>&1; then
      apt update -y && apt install -y certbot python3-certbot-nginx || true
    fi
  fi
  if ! command -v certbot >/dev/null 2>&1; then
    if command -v snap >/dev/null 2>&1; then
      snap install core || true
      snap refresh core || true
      snap install --classic certbot || true
      if [ -x /snap/bin/certbot ] && [ ! -e /usr/bin/certbot ]; then
        ln -s /snap/bin/certbot /usr/bin/certbot || true
      fi
    fi
  fi
  if command -v certbot >/dev/null 2>&1; then
    read -p "Email Let's Encrypt (wajib): " CERT_EMAIL
    if [ -n "$CERT_EMAIL" ]; then
      certbot --nginx -d "$VH_DOMAIN" -m "$CERT_EMAIL" --agree-tos --redirect --no-eff-email || true
      nginx -t && systemctl reload nginx || systemctl restart nginx
    else
      echo "Email kosong, melewati pemasangan SSL."
    fi
  else
    echo "certbot tidak tersedia, lewati pemasangan SSL."
  fi
fi

echo "Virtual host untuk ${VH_DOMAIN} selesai dibuat."
