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

NODE_VERSION_MAJOR="${NODE_VERSION_MAJOR:-24}"
echo "Memeriksa Node.js ${NODE_VERSION_MAJOR}.x..."
if command -v node >/dev/null 2>&1; then
  CURRENT_NODE="$(node -v 2>/dev/null | sed 's/^v//')"
  CURRENT_MAJOR="$(printf "%s" "$CURRENT_NODE" | cut -d. -f1)"
  if [ "$CURRENT_MAJOR" != "$NODE_VERSION_MAJOR" ]; then
    echo "Versi Node saat ini $CURRENT_NODE, menginstall Node ${NODE_VERSION_MAJOR}.x..."
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION_MAJOR}.x" | bash -
    apt install -y nodejs
  else
    echo "Node.js sudah versi ${NODE_VERSION_MAJOR}.x"
  fi
else
  echo "Node.js belum terpasang, menginstall Node ${NODE_VERSION_MAJOR}.x..."
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION_MAJOR}.x" | bash -
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
  DEFAULT_FRONTEND_REPO_URL="${DEFAULT_FRONTEND_REPO_URL:-git@github.com:sharemovie1993/absenta_frontend.git}"
  read -p "Masukkan URL repository frontend [default: $DEFAULT_FRONTEND_REPO_URL]: " FRONTEND_REPO_URL
  FRONTEND_REPO_URL=${FRONTEND_REPO_URL:-$DEFAULT_FRONTEND_REPO_URL}
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
