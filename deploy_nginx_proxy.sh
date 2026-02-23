#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

APP_ROOT="${APP_ROOT:-/var/www/absenta}"
BACKEND_PORT_DEFAULT=3000
FRONTEND_PORT_DEFAULT=8080

echo "=== Konfigurasi Nginx Reverse Proxy Absenta ==="
echo "Pilih mode topologi:"
echo "1) Multi Backend - Multi Frontend  (cluster App Server di banyak VM)"
echo "2) Multi Backend - Single Frontend (API di banyak VM, FE satu VM)"
echo "3) Single Backend - Single Frontend (default)"
read -p "Mode (1/2/3, default 3): " NGINX_MODE
NGINX_MODE=${NGINX_MODE:-3}

read -p "Server name frontend (boleh wildcard, contoh: \"*.absenta.id absenta.id\"): " FRONTEND_DOMAIN
read -p "Server name API/backend (misal api.absenta.id): " API_DOMAIN

if [ -z "$FRONTEND_DOMAIN" ] || [ -z "$API_DOMAIN" ]; then
  echo "Frontend domain dan API domain wajib diisi."
  exit 1
fi

if [ "$NGINX_MODE" = "1" ] || [ "$NGINX_MODE" = "2" ]; then
  read -p "Port backend internal default untuk API (default ${BACKEND_PORT_DEFAULT}): " BACKEND_PORT_INPUT
  BACKEND_PORT_DEFAULT=${BACKEND_PORT_INPUT:-$BACKEND_PORT_DEFAULT}
  read -p "Port frontend internal default (default ${FRONTEND_PORT_DEFAULT}): " FRONTEND_PORT_INPUT
  FRONTEND_PORT=${FRONTEND_PORT_INPUT:-$FRONTEND_PORT_DEFAULT}
else
  read -p "Host backend internal (default 127.0.0.1): " BACKEND_HOST
  BACKEND_HOST=${BACKEND_HOST:-127.0.0.1}
  read -p "Port backend internal (default ${BACKEND_PORT_DEFAULT}): " BACKEND_PORT
  BACKEND_PORT=${BACKEND_PORT:-$BACKEND_PORT_DEFAULT}
  read -p "Host frontend internal (default 127.0.0.1): " FRONTEND_HOST
  FRONTEND_HOST=${FRONTEND_HOST:-127.0.0.1}
  read -p "Port frontend internal (default ${FRONTEND_PORT_DEFAULT}): " FRONTEND_PORT
  FRONTEND_PORT=${FRONTEND_PORT:-$FRONTEND_PORT_DEFAULT}
fi

if ! command -v nginx >/dev/null 2>&1; then
  echo "Menginstall Nginx..."
  apt update -y
  apt install -y nginx
fi

NGINX_CONF="/etc/nginx/sites-available/absenta.conf"

if [ "$NGINX_MODE" = "1" ] || [ "$NGINX_MODE" = "2" ]; then
  if [ "$NGINX_MODE" = "1" ]; then
    echo "Mode: Multi Backend - Multi Frontend"
  else
    echo "Mode: Multi Backend - Single Frontend"
  fi
  read -p "Jumlah backend server untuk API (default 2): " BACKEND_COUNT
  BACKEND_COUNT=${BACKEND_COUNT:-2}
  BACKEND_UPSTREAM_SERVERS=""
  FRONTEND_UPSTREAM_SERVERS=""
  i=1
  while [ "$i" -le "$BACKEND_COUNT" ]; do
    read -p "Backend #$i host (default 127.0.0.1): " HOST
    HOST=${HOST:-127.0.0.1}
    read -p "Backend #$i port (default ${BACKEND_PORT_DEFAULT}): " PORT
    PORT=${PORT:-$BACKEND_PORT_DEFAULT}
    BACKEND_UPSTREAM_SERVERS="${BACKEND_UPSTREAM_SERVERS}    server ${HOST}:${PORT};"$'\n'
    if [ "$NGINX_MODE" = "1" ]; then
      FRONTEND_UPSTREAM_SERVERS="${FRONTEND_UPSTREAM_SERVERS}    server ${HOST}:${FRONTEND_PORT};"$'\n'
    fi
    i=$((i + 1))
  done

  if [ "$NGINX_MODE" = "1" ]; then
    # Multi Backend - Multi Frontend (cluster App Server, setiap VM punya backend+frontend)
    cat > "$NGINX_CONF" <<EOF
upstream absenta_backend_upstream {
${BACKEND_UPSTREAM_SERVERS}}

upstream absenta_frontend_upstream {
${FRONTEND_UPSTREAM_SERVERS}}

server {
  listen 80;
  server_name ${API_DOMAIN};

  client_max_body_size 20m;

  location /socket.io/ {
    proxy_pass http://absenta_backend_upstream;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }

  location /api/socket.io/ {
    proxy_pass http://absenta_backend_upstream;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }

  location / {
    proxy_pass http://absenta_backend_upstream;
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
    proxy_pass http://absenta_frontend_upstream;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF
  else
    # Multi Backend - Single Frontend (API tersebar, FE satu node)
    read -p "Host frontend internal (default 127.0.0.1): " FRONTEND_HOST
    FRONTEND_HOST=${FRONTEND_HOST:-127.0.0.1}

    cat > "$NGINX_CONF" <<EOF
upstream absenta_backend_upstream {
${BACKEND_UPSTREAM_SERVERS}}

server {
  listen 80;
  server_name ${API_DOMAIN};

  client_max_body_size 20m;

  location /socket.io/ {
    proxy_pass http://absenta_backend_upstream;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }

  location /api/socket.io/ {
    proxy_pass http://absenta_backend_upstream;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }

  location / {
    proxy_pass http://absenta_backend_upstream;
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
    proxy_pass http://${FRONTEND_HOST}:${FRONTEND_PORT};
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF
  fi
else
  # Single Backend - Single Frontend
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
fi

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/absenta.conf

if [ -f /etc/nginx/sites-enabled/default ]; then
  rm -f /etc/nginx/sites-enabled/default
fi

nginx -t
systemctl reload nginx

echo "Konfigurasi Nginx reverse proxy selesai."
if [ "$NGINX_MODE" = "1" ]; then
  echo "Frontend: http://${FRONTEND_DOMAIN} -> upstream absenta_frontend_upstream (multi-frontend)"
elif [ "$NGINX_MODE" = "2" ]; then
  echo "Frontend: http://${FRONTEND_DOMAIN} -> ${FRONTEND_HOST}:${FRONTEND_PORT}"
else
  echo "Frontend: http://${FRONTEND_DOMAIN} -> ${FRONTEND_HOST}:${FRONTEND_PORT}"
fi
if [ "$NGINX_MODE" = "1" ] || [ "$NGINX_MODE" = "2" ]; then
  echo "API:      http://${API_DOMAIN} -> upstream absenta_backend_upstream (multi-backend)"
else
  echo "API:      http://${API_DOMAIN} -> ${BACKEND_HOST}:${BACKEND_PORT}"
fi
