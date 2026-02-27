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

BACKEND_ENV_FILES=(".env")
for f in "${BACKEND_ENV_FILES[@]}"; do
  if [ -f "$f" ]; then
    cp "$f" "/tmp/absenta-backend-${f##*/}.bak" || true
  fi
done

if [ -d ".git" ]; then
  echo "Mereset perubahan lokal..."
  git reset --hard
  git fetch --all
  git pull
fi

for f in "${BACKEND_ENV_FILES[@]}"; do
  BAK="/tmp/absenta-backend-${f##*/}.bak"
  if [ -f "$BAK" ]; then
    cp "$BAK" "$f" || true
  fi
done

npm install
npx prisma generate
npx prisma migrate deploy
npx prisma db seed || true
# Seed menu & data sistem (idempotent)
if command -v npx >/dev/null 2>&1; then
  echo "Menjalankan seed.ts (menu, roles, dsb)..."
  npx ts-node -r tsconfig-paths/register prisma/seed.ts || echo "Seed prisma/seed.ts gagal (lanjutkan proses)"
else
  echo "npx tidak tersedia, melewati ts-node seed."
fi
npm run build

if pm2 list | grep -q "absenta-backend"; then
  pm2 reload absenta-backend
else
  pm2 start dist/main.js --name absenta-backend --node-args "-r tsconfig-paths/register"
fi

pm2 save

echo "▶ Update frontend..."
cd "$FRONTEND_DIR"

FRONTEND_ENV_FILES=(".env")
for f in "${FRONTEND_ENV_FILES[@]}"; do
  if [ -f "$f" ]; then
    cp "$f" "/tmp/absenta-frontend-${f##*/}.bak" || true
  fi
done

if [ -d ".git" ]; then
  echo "Mereset perubahan lokal..."
  git reset --hard
  git fetch --all
  git pull
fi

for f in "${FRONTEND_ENV_FILES[@]}"; do
  BAK="/tmp/absenta-frontend-${f##*/}.bak"
  if [ -f "$BAK" ]; then
    cp "$BAK" "$f" || true
  fi
done

npm install
npm run build

if pm2 list | grep -q "absenta-frontend"; then
  pm2 reload absenta-frontend
else
  pm2 start "serve -s dist -l 8080" --name absenta-frontend
fi

pm2 save

if command -v pm2 >/dev/null 2>&1; then
  pm2 startup systemd -u root --hp /root || true
fi

echo "=== UPDATE APP SERVER SELESAI ==="
