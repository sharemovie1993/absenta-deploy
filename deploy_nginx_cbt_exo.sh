#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

if ! command -v nginx >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y nginx
  elif command -v apt >/dev/null 2>&1; then
    apt update -y
    apt install -y nginx
  else
    echo "Package manager tidak terdeteksi. Install nginx manual."
    exit 1
  fi
fi

read -p "Domain CBT (default cbt.absenta.id): " CBT_DOMAIN
CBT_DOMAIN=${CBT_DOMAIN:-cbt.absenta.id}

read -p "Upstream host (default 127.0.0.1): " UP_HOST
UP_HOST=${UP_HOST:-127.0.0.1}
read -p "Upstream port (default 9988): " UP_PORT
UP_PORT=${UP_PORT:-9988}

CONF_DIR="/etc/nginx/sites-available"
ENABLED_DIR="/etc/nginx/sites-enabled"
mkdir -p "$CONF_DIR" "$ENABLED_DIR" || true
CONF_PATH="$CONF_DIR/cbt-exo.conf"

# Deteksi konflik server_name dan tawarkan disable
CONFLICTS=$(grep -Rsl "server_name[[:space:]]\+${CBT_DOMAIN}[; ]" /etc/nginx/sites-available /etc/nginx/sites-enabled 2>/dev/null | grep -v "^${CONF_PATH}$" || true)
if [ -n "$CONFLICTS" ]; then
  echo "Terdeteksi konfigurasi lain yang memakai server_name ${CBT_DOMAIN}:"
  echo "$CONFLICTS"
  read -p "Nonaktifkan link di sites-enabled untuk entri konflik? (y/n, default y): " DISABLE_CONFLICTS
  DISABLE_CONFLICTS=${DISABLE_CONFLICTS:-y}
  if [ "$DISABLE_CONFLICTS" = "y" ] || [ "$DISABLE_CONFLICTS" = "Y" ]; then
    for f in $CONFLICTS; do
      base="$(basename "$f")"
      if [ -L "/etc/nginx/sites-enabled/$base" ]; then
        rm -f "/etc/nginx/sites-enabled/$base" || true
        echo "Menonaktifkan /etc/nginx/sites-enabled/$base"
      fi
    done
  else
    echo "Peringatan: Konflik server_name dapat menyebabkan domain diarahkan ke layanan lain."
  fi
fi

# Siapkan map untuk koneksi WebSocket pada level http (via conf.d)
WS_MAP_FILE="/etc/nginx/conf.d/cbt_exo_ws.map.conf"
if [ ! -f "$WS_MAP_FILE" ]; then
  cat > "$WS_MAP_FILE" <<'EOM'
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
EOM
fi

cat > "$CONF_PATH" <<EOF
upstream cbt_exo_upstream {
    server ${UP_HOST}:${UP_PORT};
    keepalive 16;
}

server {
    listen 80;
    listen [::]:80;
    server_name ${CBT_DOMAIN};

    location /ws {
        proxy_pass http://cbt_exo_upstream;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$http_cf_connecting_ip;
        proxy_set_header X-Forwarded-For \$http_cf_connecting_ip;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
    }

    location /api {
        proxy_pass http://cbt_exo_upstream;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$http_cf_connecting_ip;
        proxy_set_header X-Forwarded-For \$http_cf_connecting_ip;
        proxy_set_header X-Forwarded-Proto \$scheme;
        add_header Cache-Control "no-store";
    }

    location / {
        proxy_pass http://cbt_exo_upstream;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$http_cf_connecting_ip;
        proxy_set_header X-Forwarded-For \$http_cf_connecting_ip;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    access_log /var/log/nginx/cbt_exo_access.log;
    error_log  /var/log/nginx/cbt_exo_error.log;
}
EOF

ln -sf "$CONF_PATH" "$ENABLED_DIR/cbt-exo.conf"

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

echo "Nginx untuk CBT EXO siap: http://${CBT_DOMAIN}"
