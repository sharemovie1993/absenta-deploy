#!/bin/bash
set -e

APP_ROOT="${APP_ROOT:-/var/www/absenta}"
FRONTEND_DIR="$APP_ROOT/frontend"

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

echo "Memperbarui paket sistem..."
apt update -y
apt upgrade -y

echo "Menginstall paket dasar..."
apt install -y curl git build-essential nginx

echo "Memeriksa Node.js 18..."
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
  apt install -y nodejs
fi

echo "Menginstall PM2 dan serve..."
if ! command -v pm2 >/dev/null 2>&1; then
  npm install -g pm2
fi
if ! command -v serve >/dev/null 2>&1; then
  npm install -g serve
fi

echo "Mengkonfigurasi PM2 agar auto-start saat reboot..."
pm2 startup systemd -u root --hp /root || true

mkdir -p "$APP_ROOT"

if [ ! -d "$FRONTEND_DIR/.git" ]; then
  echo "Repository frontend belum ada."
  read -p "Masukkan URL repository frontend (https): " FRONTEND_REPO_URL
  if [ -z "$FRONTEND_REPO_URL" ]; then
    echo "URL repository frontend wajib diisi."
    exit 1
  fi
  git clone "$FRONTEND_REPO_URL" "$FRONTEND_DIR"
else
  echo "Memperbarui repository frontend..."
  cd "$FRONTEND_DIR"
  git pull
fi

echo "Menyiapkan frontend..."
cd "$FRONTEND_DIR"

npm install
npm run build

if pm2 list | grep -q "absenta-frontend"; then
  pm2 reload absenta-frontend
else
  pm2 start "serve -s dist -l 8080" --name absenta-frontend
fi

pm2 save

echo "Frontend server siap berjalan."
