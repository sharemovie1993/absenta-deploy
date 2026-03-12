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
    echo "nginx tidak terpasang dan package manager tidak terdeteksi."
    exit 1
  fi
fi

read -p "Domain CBT (default cbt.absenta.id): " CBT_DOMAIN
CBT_DOMAIN=${CBT_DOMAIN:-cbt.absenta.id}

if command -v ufw >/dev/null 2>&1; then
  ufw allow 'Nginx Full' || { ufw allow 80/tcp || true; ufw allow 443/tcp || true; }
elif command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-service=http || firewall-cmd --permanent --add-port=80/tcp || true
  firewall-cmd --permanent --add-service=https || firewall-cmd --permanent --add-port=443/tcp || true
  firewall-cmd --reload || true
fi

if command -v certbot >/dev/null 2>&1; then
  :
else
  if command -v apt-get >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -y
      apt-get install -y certbot python3-certbot-nginx || true
    else
      apt update -y
      apt install -y certbot python3-certbot-nginx || true
    fi
  fi
  if ! command -v certbot >/dev/null 2>&1; then
    if ! command -v snap >/dev/null 2>&1; then
      if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y && apt-get install -y snapd || true
      elif command -v apt >/dev/null 2>&1; then
        apt update -y && apt install -y snapd || true
      fi
    fi
    if command -v snap >/dev/null 2>&1; then
      snap install core || true
      snap refresh core || true
      snap install --classic certbot || true
      if [ -x /snap/bin/certbot ] && [ ! -e /usr/bin/certbot ]; then
        ln -s /snap/bin/certbot /usr/bin/certbot || true
      fi
    fi
  fi
fi

if ! command -v certbot >/dev/null 2>&1; then
  echo "certbot tidak tersedia. Pasang certbot terlebih dahulu."
  exit 1
fi

systemctl enable nginx
systemctl reload nginx || systemctl restart nginx

read -p "Email untuk Let's Encrypt (wajib): " CERT_EMAIL
if [ -z "$CERT_EMAIL" ]; then
  echo "Email wajib diisi."
  exit 1
fi

certbot --nginx -d "$CBT_DOMAIN" -m "$CERT_EMAIL" --agree-tos --redirect --no-eff-email || {
  echo "Otomasi plugin nginx gagal. Mencoba metode webroot."
  mkdir -p /var/www/letsencrypt
  if ! grep -q "location /.well-known/acme-challenge/" "/etc/nginx/sites-available/cbt-exo.conf" 2>/dev/null; then
    cat >> "/etc/nginx/sites-available/cbt-exo.conf" <<EOF
location /.well-known/acme-challenge/ {
    root /var/www/letsencrypt;
}
EOF
    ln -sf "/etc/nginx/sites-available/cbt-exo.conf" "/etc/nginx/sites-enabled/cbt-exo.conf"
    nginx -t && systemctl reload nginx || systemctl restart nginx
  fi
  certbot certonly --webroot -w /var/www/letsencrypt -d "$CBT_DOMAIN" -m "$CERT_EMAIL" --agree-tos --no-eff-email --non-interactive || exit 1
  if [ -d "/etc/letsencrypt/live/$CBT_DOMAIN" ]; then
    if ! grep -q "listen 443" "/etc/nginx/sites-available/cbt-exo.conf" 2>/dev/null; then
      cat >> "/etc/nginx/sites-available/cbt-exo.conf" <<EOF
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${CBT_DOMAIN};
    ssl_certificate /etc/letsencrypt/live/${CBT_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${CBT_DOMAIN}/privkey.pem;
    location / {
        proxy_pass http://cbt_exo_upstream;
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
    if ! grep -q "return 301 https://" "/etc/nginx/sites-available/cbt-exo.conf" 2>/dev/null; then
      sed -i "s|location / {|location / {\\n        return 301 https://\$host\$request_uri;\\n    }\\n\\n    location /old_http_keep {|" "/etc/nginx/sites-available/cbt-exo.conf" || true
    fi
  fi
}

nginx -t
systemctl reload nginx || systemctl restart nginx

certbot renew --dry-run || true

echo "SSL Let's Encrypt untuk ${CBT_DOMAIN} selesai dipasang."
