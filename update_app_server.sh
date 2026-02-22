#!/bin/bash
set -e

APP_ROOT="${APP_ROOT:-/var/www/absenta}"
BACKEND_DIR="$APP_ROOT/backend"
FRONTEND_DIR="$APP_ROOT/frontend"

if [ "$EUID" -ne 0 ]; then
  echo "Script ini sebaiknya dijalankan sebagai root (sudo)."
  exit 1
fi

echo "=== UPDATE APP SERVER (BACKEND + FRONTEND) ==="

if [ ! -d "$BACKEND_DIR" ]; then
  echo "Direktori backend $BACKEND_DIR tidak ditemukan."
  exit 1
fi

if [ ! -d "$FRONTEND_DIR" ]; then
  echo "Direktori frontend $FRONTEND_DIR tidak ditemukan."
  exit 1
fi

echo "▶ Update backend..."
cd "$BACKEND_DIR"

if [ -d ".git" ]; then
  git fetch --all
  git pull
fi

npm install
npx prisma generate
npx prisma migrate deploy
npm run build

if pm2 list | grep -q "absenta-backend"; then
  pm2 reload absenta-backend
else
  pm2 start dist/main.js --name absenta-backend --node-args "-r tsconfig-paths/register"
fi

pm2 save

echo "▶ Update frontend..."
cd "$FRONTEND_DIR"

if [ -d ".git" ]; then
  git fetch --all
  git pull
fi

npm install
npm run build

if pm2 list | grep -q "absenta-frontend"; then
  pm2 reload absenta-frontend
else
  pm2 start "serve -s dist -l 8080" --name absenta-frontend
fi

pm2 save

echo "=== UPDATE APP SERVER SELESAI ==="

