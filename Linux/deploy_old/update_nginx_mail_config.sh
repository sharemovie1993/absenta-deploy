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

MAIL_INTERNAL_PORT_DEFAULT="443"
read -p "Port internal mail server (default ${MAIL_INTERNAL_PORT_DEFAULT}): " MAIL_INTERNAL_PORT
MAIL_INTERNAL_PORT=${MAIL_INTERNAL_PORT:-$MAIL_INTERNAL_PORT_DEFAULT}

NGINX_CONF_AVAILABLE="/etc/nginx/sites-available/mail.absenta.conf"
NGINX_CONF_ENABLED="/etc/nginx/sites-enabled/mail.absenta.conf"

echo "Menulis konfigurasi Nginx ke ${NGINX_CONF_AVAILABLE} ..."
echo "Target: ${MAIL_DOMAIN} -> ${MAIL_INTERNAL_HOST}:${MAIL_INTERNAL_PORT}"

# Buat konfigurasi Nginx khusus untuk mail
# Gunakan HTTPS ke upstream untuk menghindari Redirect Loop (ERR_TOO_MANY_REDIRECTS)
cat > "$NGINX_CONF_AVAILABLE" <<EOF
server {
    listen 80;
    server_name ${MAIL_DOMAIN};
    
    # Redirect HTTP ke HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${MAIL_DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${CERT_DOMAIN}/privkey.pem;

    # SSL Optimasi
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Proxy ke Mailcow (Internal) menggunakan HTTPS
    # Kita ignore SSL verify karena sertifikat internal mungkin self-signed atau tidak cocok hostname
    location / {
        proxy_pass https://${MAIL_INTERNAL_HOST}:${MAIL_INTERNAL_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        
        # Penting untuk Mailcow + Reverse Proxy
        proxy_ssl_verify off;
        proxy_ssl_session_reuse on;

        # WebSocket support (jika dibutuhkan oleh SOGo/ActiveSync)
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # Timeouts
        proxy_connect_timeout 600;
        proxy_send_timeout 600;
        proxy_read_timeout 600;
        send_timeout 600;
        client_max_body_size 100M;
    }
}
EOF

# Link ke sites-enabled
ln -sf "$NGINX_CONF_AVAILABLE" "$NGINX_CONF_ENABLED"

echo "Konfigurasi berhasil ditulis ke: $NGINX_CONF_ENABLED"
echo "---------------------------------------------------"
cat "$NGINX_CONF_ENABLED"
echo "---------------------------------------------------"
echo "CATATAN PENTING:"
echo "1. Pastikan DNS Record untuk '${MAIL_DOMAIN}' di Cloudflare diset ke 'DNS Only' (Awan Abu-abu)."
echo "   Jika masih 'Proxied' (Awan Oranye), Anda akan mengalami error 'Too Many Redirects'."
echo "2. File ini TERPISAH dari absenta.conf untuk menghindari konflik wildcard."
echo "---------------------------------------------------"

echo "Memeriksa konfigurasi Nginx..."
nginx -t

echo "Reload Nginx..."
systemctl reload nginx

echo "Update konfigurasi Nginx untuk mail selesai."

