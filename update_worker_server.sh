#!/bin/bash
set -e

APP_ROOT="${APP_ROOT:-/var/www/absenta}"
BACKEND_DIR="$APP_ROOT/backend"

if [ "$EUID" -ne 0 ]; then
  echo "Script ini sebaiknya dijalankan sebagai root (sudo)."
  exit 1
fi

echo "=== UPDATE WORKER SERVER ==="

if [ ! -d "$BACKEND_DIR" ]; then
  echo "Direktori backend $BACKEND_DIR tidak ditemukan."
  exit 1
fi

cd "$BACKEND_DIR"

if [ -d ".git" ]; then
  git fetch --all
  git pull
fi

npm install
npx prisma generate

if pm2 list | grep -q "absenta-worker"; then
  pm2 restart absenta-worker
else
  pm2 start "npm run worker" --name absenta-worker
fi

pm2 save

echo "=== UPDATE WORKER SERVER SELESAI ==="

