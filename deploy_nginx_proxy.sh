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

DEFAULT_CERT_DOMAIN=$(echo "$FRONTEND_DOMAIN" | awk '{print $NF}' | sed 's/^\*\.//')
read -p "Base domain sertifikat SSL (default ${DEFAULT_CERT_DOMAIN}): " CERT_DOMAIN
CERT_DOMAIN=${CERT_DOMAIN:-$DEFAULT_CERT_DOMAIN}

FRONTEND_SERVER_NAME="$FRONTEND_DOMAIN"
if ! echo "$FRONTEND_SERVER_NAME" | grep -qw "$CERT_DOMAIN"; then
  FRONTEND_SERVER_NAME="$FRONTEND_SERVER_NAME $CERT_DOMAIN"
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
    BACKEND_UPSTREAM_SERVERS="${BACKEND_UPSTREAM_SERVERS}    server ${HOST}:${PORT} max_fails=3 fail_timeout=30s;"$'\n'
    if [ "$NGINX_MODE" = "1" ]; then
      FRONTEND_UPSTREAM_SERVERS="${FRONTEND_UPSTREAM_SERVERS}    server ${HOST}:${FRONTEND_PORT} max_fails=3 fail_timeout=30s;"$'\n'
    fi
    i=$((i + 1))
  done

  if [ "$NGINX_MODE" = "1" ]; then
    cat > "$NGINX_CONF" <<EOF
upstream absenta_backend_upstream {
  least_conn;
${BACKEND_UPSTREAM_SERVERS}
  keepalive 64;
}

upstream absenta_frontend_upstream {
  least_conn;
${FRONTEND_UPSTREAM_SERVERS}
  keepalive 64;
}

server {
  listen 80;
  server_name ${API_DOMAIN};

  return 301 https://\$host\$request_uri;
}

server {
  listen 443 ssl http2;
  server_name ${API_DOMAIN};

  ssl_certificate /etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/${CERT_DOMAIN}/privkey.pem;

  location / {
    if (\$request_method = 'OPTIONS') {
      add_header 'Access-Control-Allow-Origin' "\$http_origin" always;
      add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, PATCH, DELETE, OPTIONS' always;
      add_header 'Access-Control-Allow-Headers' 'authorization, content-type, x-tenant-sub, x-tenant-host, x-tenant-domain, x-tenant-id, x-skip-tenant, x-skip-403-redirect, x-requested-with, accept, origin, user-agent, x-socket-id' always;
      add_header 'Access-Control-Allow-Credentials' 'true' always;
      add_header 'Access-Control-Max-Age' 86400 always;
      add_header 'Content-Type' 'text/plain; charset=utf-8';
      add_header 'Content-Length' 0;
      return 204;
    }

    add_header 'Access-Control-Allow-Origin' "\$http_origin" always;
    add_header 'Access-Control-Allow-Credentials' 'true' always;
    add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, PATCH, DELETE, OPTIONS' always;
    add_header 'Access-Control-Allow-Headers' 'authorization, content-type, x-tenant-sub, x-tenant-host, x-tenant-domain, x-tenant-id, x-skip-tenant, x-skip-403-redirect, x-requested-with, accept, origin, user-agent, x-socket-id' always;

    proxy_hide_header 'Access-Control-Allow-Origin';
    proxy_hide_header 'Access-Control-Allow-Credentials';
    proxy_hide_header 'Access-Control-Allow-Methods';
    proxy_hide_header 'Access-Control-Allow-Headers';

    proxy_pass http://absenta_backend_upstream;
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_connect_timeout 5s;
    proxy_send_timeout 30s;
    proxy_read_timeout 60s;
    proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
  }
}

server {
  listen 80;
  server_name ${FRONTEND_SERVER_NAME};
  return 301 https://\$host\$request_uri;
}

server {
  listen 443 ssl http2;
  server_name ${FRONTEND_SERVER_NAME};

  ssl_certificate /etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/${CERT_DOMAIN}/privkey.pem;

  location ^~ /webhooks/ {
    proxy_pass http://absenta_backend_upstream;
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }

  location ^~ /payment/ {
    proxy_pass http://absenta_backend_upstream;
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }

  location ^~ /invoice/public/ {
    proxy_pass http://absenta_backend_upstream;
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }

  # Serve static assets explicitly to frontend upstream to avoid SPA fallbacks returning HTML
  location ^~ /assets/ {
    proxy_pass http://absenta_frontend_upstream;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
  location ~* \.(js|css|map|svg|png|jpe?g|webp|woff2?)\$ {
    proxy_pass http://absenta_frontend_upstream;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    expires 7d;
    add_header Cache-Control "public, max-age=604800, immutable";
  }

  location /api/ {
    if (\$request_method = 'OPTIONS') {
      add_header 'Access-Control-Allow-Origin' "\$http_origin" always;
      add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, PATCH, DELETE, OPTIONS' always;
      add_header 'Access-Control-Allow-Headers' 'authorization, content-type, x-tenant-sub, x-tenant-host, x-tenant-domain, x-tenant-id, x-skip-tenant, x-skip-403-redirect, x-requested-with, accept, origin, user-agent, x-socket-id' always;
      add_header 'Access-Control-Allow-Credentials' 'true' always;
      add_header 'Access-Control-Max-Age' 86400 always;
      add_header 'Content-Type' 'text/plain; charset=utf-8';
      add_header 'Content-Length' 0;
      return 204;
    }

    add_header 'Access-Control-Allow-Origin' "\$http_origin" always;
    add_header 'Access-Control-Allow-Credentials' 'true' always;
    add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, PATCH, DELETE, OPTIONS' always;
    add_header 'Access-Control-Allow-Headers' 'authorization, content-type, x-tenant-sub, x-tenant-host, x-tenant-domain, x-tenant-id, x-skip-tenant, x-skip-403-redirect, x-requested-with, accept, origin, user-agent, x-socket-id' always;

    proxy_hide_header 'Access-Control-Allow-Origin';
    proxy_hide_header 'Access-Control-Allow-Credentials';
    proxy_hide_header 'Access-Control-Allow-Methods';
    proxy_hide_header 'Access-Control-Allow-Headers';

    proxy_pass http://absenta_backend_upstream;
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_connect_timeout 5s;
    proxy_send_timeout 30s;
    proxy_read_timeout 60s;
    proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
  }

  location /socket.io/ {
    proxy_pass http://absenta_backend_upstream;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_connect_timeout 5s;
    proxy_read_timeout 300s;
    proxy_next_upstream error timeout http_502 http_503 http_504;
  }

  location = /sw.js {
    proxy_pass http://absenta_frontend_upstream;
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0";
    expires off;
    add_header Service-Worker-Allowed "/";
  }

  location = /manifest.webmanifest {
    proxy_pass http://absenta_frontend_upstream;
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    add_header Content-Type "application/manifest+json";
    add_header Cache-Control "no-cache";
  }

  location = /manifest.json {
    proxy_pass http://absenta_frontend_upstream;
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    add_header Content-Type "application/manifest+json";
    add_header Cache-Control "no-cache";
  }

  location / {
    proxy_pass http://absenta_frontend_upstream;
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_connect_timeout 5s;
    proxy_send_timeout 30s;
    proxy_read_timeout 60s;
    proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
  }
}
EOF
  else
    read -p "Host frontend internal (default 127.0.0.1): " FRONTEND_HOST
    FRONTEND_HOST=${FRONTEND_HOST:-127.0.0.1}

    cat > "$NGINX_CONF" <<EOF
upstream absenta_backend_upstream {
  least_conn;
${BACKEND_UPSTREAM_SERVERS}
  keepalive 64;
}

server {
  listen 80;
  server_name ${API_DOMAIN};

  return 301 https://\$host\$request_uri;
}

server {
  listen 443 ssl http2;
  server_name ${API_DOMAIN};

  ssl_certificate /etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/${CERT_DOMAIN}/privkey.pem;

  location / {
    if (\$request_method = 'OPTIONS') {
      add_header 'Access-Control-Allow-Origin' "\$http_origin" always;
      add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, PATCH, DELETE, OPTIONS' always;
      add_header 'Access-Control-Allow-Headers' 'authorization, content-type, x-tenant-sub, x-tenant-host, x-tenant-domain, x-tenant-id, x-skip-tenant, x-skip-403-redirect, x-requested-with, accept, origin, user-agent, x-socket-id' always;
      add_header 'Access-Control-Allow-Credentials' 'true' always;
      add_header 'Access-Control-Max-Age' 86400 always;
      add_header 'Content-Type' 'text/plain; charset=utf-8';
      add_header 'Content-Length' 0;
      return 204;
    }

    add_header 'Access-Control-Allow-Origin' "\$http_origin" always;
    add_header 'Access-Control-Allow-Credentials' 'true' always;
    add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, PATCH, DELETE, OPTIONS' always;
    add_header 'Access-Control-Allow-Headers' 'authorization, content-type, x-tenant-sub, x-tenant-host, x-tenant-domain, x-tenant-id, x-skip-tenant, x-skip-403-redirect, x-requested-with, accept, origin, user-agent, x-socket-id' always;

    proxy_hide_header 'Access-Control-Allow-Origin';
    proxy_hide_header 'Access-Control-Allow-Credentials';
    proxy_hide_header 'Access-Control-Allow-Methods';
    proxy_hide_header 'Access-Control-Allow-Headers';

    proxy_pass http://absenta_backend_upstream;
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_connect_timeout 5s;
    proxy_send_timeout 30s;
    proxy_read_timeout 60s;
    proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
  }
}

server {
  listen 80;
  server_name ${FRONTEND_SERVER_NAME};

  return 301 https://\$host\$request_uri;
}

server {
  listen 443 ssl http2;
  server_name ${FRONTEND_SERVER_NAME};

  ssl_certificate /etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/${CERT_DOMAIN}/privkey.pem;

  location ^~ /webhooks/ {
    proxy_pass http://absenta_backend_upstream;
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }

  location ^~ /payment/ {
    proxy_pass http://absenta_backend_upstream;
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }

  location ^~ /invoice/public/ {
    proxy_pass http://absenta_backend_upstream;
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }

  location /api/ {
    if (\$request_method = 'OPTIONS') {
      add_header 'Access-Control-Allow-Origin' "\$http_origin" always;
      add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, PATCH, DELETE, OPTIONS' always;
      add_header 'Access-Control-Allow-Headers' 'authorization, content-type, x-tenant-sub, x-tenant-host, x-tenant-domain, x-tenant-id, x-skip-tenant, x-skip-403-redirect, x-requested-with, accept, origin, user-agent, x-socket-id' always;
      add_header 'Access-Control-Allow-Credentials' 'true' always;
      add_header 'Access-Control-Max-Age' 86400 always;
      add_header 'Content-Type' 'text/plain; charset=utf-8';
      add_header 'Content-Length' 0;
      return 204;
    }

    add_header 'Access-Control-Allow-Origin' "\$http_origin" always;
    add_header 'Access-Control-Allow-Credentials' 'true' always;
    add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, PATCH, DELETE, OPTIONS' always;
    add_header 'Access-Control-Allow-Headers' 'authorization, content-type, x-tenant-sub, x-tenant-host, x-tenant-domain, x-tenant-id, x-skip-tenant, x-skip-403-redirect, x-requested-with, accept, origin, user-agent, x-socket-id' always;

    proxy_hide_header 'Access-Control-Allow-Origin';
    proxy_hide_header 'Access-Control-Allow-Credentials';
    proxy_hide_header 'Access-Control-Allow-Methods';
    proxy_hide_header 'Access-Control-Allow-Headers';

    proxy_pass http://absenta_backend_upstream;
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_connect_timeout 5s;
    proxy_send_timeout 30s;
    proxy_read_timeout 60s;
    proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
  }

  location /socket.io/ {
    proxy_pass http://absenta_backend_upstream;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_connect_timeout 5s;
    proxy_read_timeout 300s;
    proxy_next_upstream error timeout http_502 http_503 http_504;
  }

  location = /sw.js {
    proxy_pass http://${FRONTEND_HOST}:${FRONTEND_PORT};
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0";
    expires off;
    add_header Service-Worker-Allowed "/";
  }

  location = /manifest.webmanifest {
    proxy_pass http://${FRONTEND_HOST}:${FRONTEND_PORT};
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    add_header Content-Type "application/manifest+json";
    add_header Cache-Control "no-cache";
  }

  location = /manifest.json {
    proxy_pass http://${FRONTEND_HOST}:${FRONTEND_PORT};
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    add_header Content-Type "application/manifest+json";
    add_header Cache-Control "no-cache";
  }

  location / {
    proxy_pass http://${FRONTEND_HOST}:${FRONTEND_PORT};
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF
  fi
else
  cat > "$NGINX_CONF" <<EOF
server {
  listen 80;
  server_name ${API_DOMAIN};

  return 301 https://\$host\$request_uri;
}

server {
  listen 443 ssl http2;
  server_name ${API_DOMAIN};

  ssl_certificate /etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/${CERT_DOMAIN}/privkey.pem;

  location / {
    if (\$request_method = 'OPTIONS') {
      add_header 'Access-Control-Allow-Origin' "\$http_origin" always;
      add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, PATCH, DELETE, OPTIONS' always;
      add_header 'Access-Control-Allow-Headers' 'authorization, content-type, x-tenant-sub, x-tenant-host, x-tenant-domain, x-tenant-id, x-skip-tenant, x-skip-403-redirect, x-requested-with, accept, origin, user-agent, x-socket-id' always;
      add_header 'Access-Control-Allow-Credentials' 'true' always;
      add_header 'Access-Control-Max-Age' 86400 always;
      add_header 'Content-Type' 'text/plain; charset=utf-8';
      add_header 'Content-Length' 0;
      return 204;
    }

    add_header 'Access-Control-Allow-Origin' "\$http_origin" always;
    add_header 'Access-Control-Allow-Credentials' 'true' always;
    add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, PATCH, DELETE, OPTIONS' always;
    add_header 'Access-Control-Allow-Headers' 'authorization, content-type, x-tenant-sub, x-tenant-host, x-tenant-domain, x-tenant-id, x-skip-tenant, x-skip-403-redirect, x-requested-with, accept, origin, user-agent, x-socket-id' always;

    proxy_hide_header 'Access-Control-Allow-Origin';
    proxy_hide_header 'Access-Control-Allow-Credentials';
    proxy_hide_header 'Access-Control-Allow-Methods';
    proxy_hide_header 'Access-Control-Allow-Headers';

    proxy_pass http://${BACKEND_HOST}:${BACKEND_PORT};
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
  }
}

server {
  listen 80;
  server_name ${FRONTEND_SERVER_NAME};

  return 301 https://\$host\$request_uri;
}

server {
  listen 443 ssl http2;
  server_name ${FRONTEND_SERVER_NAME};

  ssl_certificate /etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/${CERT_DOMAIN}/privkey.pem;

  location ^~ /webhooks/ {
    proxy_pass http://${BACKEND_HOST}:${BACKEND_PORT};
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }

  location ^~ /payment/ {
    proxy_pass http://${BACKEND_HOST}:${BACKEND_PORT};
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }

  location ^~ /invoice/public/ {
    proxy_pass http://${BACKEND_HOST}:${BACKEND_PORT};
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }

  # Serve static assets explicitly to frontend host to avoid SPA fallbacks returning HTML
  location ^~ /assets/ {
    proxy_pass http://${FRONTEND_HOST}:${FRONTEND_PORT};
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
  location ~* \.(js|css|map|svg|png|jpe?g|webp|woff2?)\$ {
    proxy_pass http://${FRONTEND_HOST}:${FRONTEND_PORT};
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    expires 7d;
    add_header Cache-Control "public, max-age=604800, immutable";
  }

  location /api/ {
    if (\$request_method = 'OPTIONS') {
      add_header 'Access-Control-Allow-Origin' "\$http_origin" always;
      add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, PATCH, DELETE, OPTIONS' always;
      add_header 'Access-Control-Allow-Headers' 'authorization, content-type, x-tenant-sub, x-tenant-host, x-tenant-domain, x-tenant-id, x-skip-tenant, x-skip-403-redirect, x-requested-with, accept, origin, user-agent, x-socket-id' always;
      add_header 'Access-Control-Allow-Credentials' 'true' always;
      add_header 'Access-Control-Max-Age' 86400 always;
      add_header 'Content-Type' 'text/plain; charset=utf-8';
      add_header 'Content-Length' 0;
      return 204;
    }

    add_header 'Access-Control-Allow-Origin' "\$http_origin" always;
    add_header 'Access-Control-Allow-Credentials' 'true' always;
    add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, PATCH, DELETE, OPTIONS' always;
    add_header 'Access-Control-Allow-Headers' 'authorization, content-type, x-tenant-sub, x-tenant-host, x-tenant-domain, x-tenant-id, x-skip-tenant, x-skip-403-redirect, x-requested-with, accept, origin, user-agent, x-socket-id' always;

    proxy_hide_header 'Access-Control-Allow-Origin';
    proxy_hide_header 'Access-Control-Allow-Credentials';
    proxy_hide_header 'Access-Control-Allow-Methods';
    proxy_hide_header 'Access-Control-Allow-Headers';

    proxy_pass http://${BACKEND_HOST}:${BACKEND_PORT};
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
  }

  location /socket.io/ {
    proxy_pass http://${BACKEND_HOST}:${BACKEND_PORT};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }

  location = /sw.js {
    proxy_pass http://${FRONTEND_HOST}:${FRONTEND_PORT};
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0";
    expires off;
    add_header Service-Worker-Allowed "/";
  }

  location = /manifest.webmanifest {
    proxy_pass http://${FRONTEND_HOST}:${FRONTEND_PORT};
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    add_header Content-Type "application/manifest+json";
    add_header Cache-Control "no-cache";
  }

  location = /manifest.json {
    proxy_pass http://${FRONTEND_HOST}:${FRONTEND_PORT};
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    add_header Content-Type "application/manifest+json";
    add_header Cache-Control "no-cache";
  }

  location / {
    proxy_pass http://${FRONTEND_HOST}:${FRONTEND_PORT};
    proxy_set_header Host \$host;
    proxy_set_header X-Tenant-Subdomain \$tenant_subdomain;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF
fi

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/absenta.conf

if [ -L /etc/nginx/sites-enabled/absenta ] && [ ! -e /etc/nginx/sites-enabled/absenta ]; then
  rm -f /etc/nginx/sites-enabled/absenta
fi

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
