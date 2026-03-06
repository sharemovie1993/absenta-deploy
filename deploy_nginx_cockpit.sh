#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

# Pastikan nginx ada
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

read -p "Domain Cockpit (contoh cockpit.absenta.id): " COCKPIT_DOMAIN
if [ -z "$COCKPIT_DOMAIN" ]; then
  echo "Domain wajib diisi."
  exit 1
fi

# File map untuk WebSocket
WS_MAP_FILE="/etc/nginx/conf.d/cockpit_ws.map.conf"
if [ ! -f "$WS_MAP_FILE" ]; then
  cat > "$WS_MAP_FILE" <<'EOF'
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
EOF
fi

CONF_DIR="/etc/nginx/sites-available"
ENABLED_DIR="/etc/nginx/sites-enabled"
mkdir -p "$CONF_DIR" "$ENABLED_DIR" || true
CONF_PATH="$CONF_DIR/cockpit-$COCKPIT_DOMAIN.conf"

# Buat server block HTTP yang mem-proxy ke 9090 (certbot akan menambahkan SSL/redirect)
cat > "$CONF_PATH" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${COCKPIT_DOMAIN};

    location / {
        proxy_pass https://127.0.0.1:9090;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_ssl_server_name on;
        proxy_ssl_verify off;
    }

    access_log /var/log/nginx/${COCKPIT_DOMAIN}_access.log;
    error_log  /var/log/nginx/${COCKPIT_DOMAIN}_error.log;
}
EOF

ln -sf "$CONF_PATH" "$ENABLED_DIR/cockpit-$COCKPIT_DOMAIN.conf"

# Buka firewall 80/443
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

# cockpit.conf untuk reverse proxy
COCKPIT_CONF_DIR="/etc/cockpit"
mkdir -p "$COCKPIT_CONF_DIR" || true
COCKPIT_CONF="$COCKPIT_CONF_DIR/cockpit.conf"
if [ -f "$COCKPIT_CONF" ]; then
  TS="$(date +%Y%m%d%H%M%S)"
  cp "$COCKPIT_CONF" "${COCKPIT_CONF}.bak_$TS" || true
fi
cat > "$COCKPIT_CONF" <<EOF
[WebService]
Origins = https://${COCKPIT_DOMAIN}
ProtocolHeader = X-Forwarded-Proto
EOF

systemctl restart cockpit || systemctl restart cockpit.socket || true

# Pasang SSL Let's Encrypt
read -p "Pasang SSL Let's Encrypt sekarang untuk ${COCKPIT_DOMAIN}? (y/n, default y): " INSTALL_SSL
INSTALL_SSL=${INSTALL_SSL:-y}
if [ "$INSTALL_SSL" = "y" ] || [ "$INSTALL_SSL" = "Y" ]; then
  if ! command -v certbot >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -y && apt-get install -y certbot python3-certbot-nginx || true
    elif command -v apt >/dev/null 2>&1; then
      apt update -y && apt install -y certbot python3-certbot-nginx || true
    fi
    if ! command -v certbot >/dev/null 2>&1 && command -v snap >/dev/null 2>&1; then
      snap install core || true
      snap refresh core || true
      snap install --classic certbot || true
      [ -x /snap/bin/certbot ] && [ ! -e /usr/bin/certbot ] && ln -s /snap/bin/certbot /usr/bin/certbot || true
    fi
  fi
  if command -v certbot >/dev/null 2>&1; then
    read -p "Email Let's Encrypt (wajib): " CERT_EMAIL
    if [ -n "$CERT_EMAIL" ]; then
      certbot --nginx -d "$COCKPIT_DOMAIN" -m "$CERT_EMAIL" --agree-tos --redirect --no-eff-email || true
      nginx -t && systemctl reload nginx || systemctl restart nginx
    else
      echo "Email kosong, lewati pemasangan SSL."
    fi
  else
    echo "certbot tidak tersedia, lewati pemasangan SSL."
  fi
fi

echo "Nginx reverse proxy untuk Cockpit di https://${COCKPIT_DOMAIN} selesai."
