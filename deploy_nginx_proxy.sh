#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

APP_ROOT="${APP_ROOT:-/var/www/absenta}"
BACKEND_PORT_DEFAULT=3000
FRONTEND_PORT_DEFAULT=8080

read -p "Domain frontend (misal app.absenta.id): " FRONTEND_DOMAIN
read -p "Domain API/backend (misal api.absenta.id): " API_DOMAIN

if [ -z "$FRONTEND_DOMAIN" ] || [ -z "$API_DOMAIN" ]; then
  echo "Frontend domain dan API domain wajib diisi."
  exit 1
fi

read -p "Port backend internal (default ${BACKEND_PORT_DEFAULT}): " BACKEND_PORT
read -p "Port frontend internal (default ${FRONTEND_PORT_DEFAULT}): " FRONTEND_PORT

BACKEND_PORT=${BACKEND_PORT:-$BACKEND_PORT_DEFAULT}
FRONTEND_PORT=${FRONTEND_PORT:-$FRONTEND_PORT_DEFAULT}

if ! command -v nginx >/dev/null 2>&1; then
  echo "Menginstall Nginx..."
  apt update -y
  apt install -y nginx
fi

NGINX_CONF="/etc/nginx/sites-available/absenta.conf"

cat > "$NGINX_CONF" <<EOF
server {
  listen 80;
  server_name ${API_DOMAIN};

  client_max_body_size 20m;

  location /socket.io/ {
    proxy_pass http://127.0.0.1:${BACKEND_PORT};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }

  location /api/socket.io/ {
    proxy_pass http://127.0.0.1:${BACKEND_PORT};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }

  location / {
    proxy_pass http://127.0.0.1:${BACKEND_PORT};
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}

server {
  listen 80;
  server_name ${FRONTEND_DOMAIN};

  client_max_body_size 20m;

  location / {
    proxy_pass http://127.0.0.1:${FRONTEND_PORT};
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/absenta.conf

if [ -f /etc/nginx/sites-enabled/default ]; then
  rm -f /etc/nginx/sites-enabled/default
fi

nginx -t
systemctl reload nginx

echo "Konfigurasi Nginx reverse proxy selesai."
echo "Frontend: http://${FRONTEND_DOMAIN} -> 127.0.0.1:${FRONTEND_PORT}"
echo "API:      http://${API_DOMAIN} -> 127.0.0.1:${BACKEND_PORT}"

