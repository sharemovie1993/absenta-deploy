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

echo "=== Deploy Backend Artifact ke VM2 ==="
read -p "Host VM2 untuk backend (contoh: vm2-app-absenta atau IP, kosongkan untuk skip): " VM2_BACKEND_HOST_INPUT
VM2_BACKEND_HOST="${VM2_BACKEND_HOST_INPUT:-}"
if [ -n "$VM2_BACKEND_HOST" ]; then
  read -p "User VM2 (default root): " VM2_BACKEND_USER_INPUT
  VM2_BACKEND_USER="${VM2_BACKEND_USER_INPUT:-root}"
  read -p "Path backend di VM2 (default /var/www/absenta/backend): " VM2_BACKEND_PATH_INPUT
  VM2_BACKEND_PATH="${VM2_BACKEND_PATH_INPUT:-/var/www/absenta/backend}"
  BACKEND_ARTIFACT="backend.tar.gz"
  cd "$BACKEND_DIR"
  rm -f "$BACKEND_ARTIFACT" || true
  # Sertakan dist + package.json + package-lock.json untuk sinkronisasi dependency
  tar -czf "$BACKEND_ARTIFACT" dist package.json package-lock.json
  # Hitung hash lock lokal untuk verifikasi di VM2
  LOCAL_LOCK_HASH=""
  if [ -f "package-lock.json" ]; then
    LOCAL_LOCK_HASH="$(sha256sum package-lock.json | awk '{print $1}')"
  fi
  scp -o StrictHostKeyChecking=no "$BACKEND_ARTIFACT" "${VM2_BACKEND_USER}@${VM2_BACKEND_HOST}:${VM2_BACKEND_PATH}/"
  ssh -o StrictHostKeyChecking=no "${VM2_BACKEND_USER}@${VM2_BACKEND_HOST}" bash -c "'
    set -e
    cd \"${VM2_BACKEND_PATH}\"
    rm -rf dist
    tar -xzf \"${BACKEND_ARTIFACT}\"
    rm -f \"${BACKEND_ARTIFACT}\"
    # Jika package-lock.json berubah, jalankan npm ci --omit=dev dan prisma generate
    NEED_INSTALL=false
    if [ -f package-lock.json ]; then
      REMOTE_LOCK_HASH=\$(sha256sum package-lock.json | awk \"{print \\$1}\")
      # Simpan hash lama jika ada
      if [ -f package-lock.json.prev ]; then
        PREV_LOCK_HASH=\$(sha256sum package-lock.json.prev | awk \"{print \\$1}\")
      else
        PREV_LOCK_HASH=\"\"
      fi
      # Update snapshot prev untuk perbandingan berikutnya
      cp -f package-lock.json package-lock.json.prev || true
      # Tandai NEED_INSTALL jika hash berbeda atau node_modules tidak ada
      if [ \"\$PREV_LOCK_HASH\" != \"\$REMOTE_LOCK_HASH\" ] || [ ! -d node_modules ]; then
        NEED_INSTALL=true
      fi
    else
      # Tidak ada lock file, jalankan install jika node_modules kosong
      if [ ! -d node_modules ]; then
        NEED_INSTALL=true
      fi
    fi
    if [ \"\$NEED_INSTALL\" = true ]; then
      if command -v npm >/dev/null 2>&1; then
        npm ci --omit=dev || npm install --omit=dev
      fi
      if command -v npx >/dev/null 2>&1; then
        npx prisma generate || true
      fi
    fi
    if command -v pm2 >/dev/null 2>&1; then
      if pm2 list | grep -q \"absenta-backend\"; then
        pm2 reload absenta-backend || true
      else
        pm2 start dist/main.js --name absenta-backend --node-args \"-r tsconfig-paths/register\" || true
      fi
      pm2 save || true
    fi
  '"
fi

echo "=== Deploy Frontend Artifact ke VM2 ==="
read -p "Host VM2 (contoh: vm2-app-absenta atau IP, kosongkan untuk skip): " VM2_HOST_INPUT
VM2_HOST="${VM2_HOST_INPUT:-}"
if [ -n "$VM2_HOST" ]; then
  read -p "User VM2 (default root): " VM2_USER_INPUT
  VM2_USER="${VM2_USER_INPUT:-root}"
  read -p "Path frontend di VM2 (default /var/www/absenta/frontend): " VM2_PATH_INPUT
  VM2_PATH="${VM2_PATH_INPUT:-/var/www/absenta/frontend}"
  ARTIFACT_NAME="frontend.tar.gz"
  cd "$FRONTEND_DIR"
  rm -f "$ARTIFACT_NAME" || true
  tar -czf "$ARTIFACT_NAME" dist
  LOCAL_HASH="$(sha256sum "$ARTIFACT_NAME" | awk '{print $1}')"
  scp -o StrictHostKeyChecking=no "$ARTIFACT_NAME" "${VM2_USER}@${VM2_HOST}:${VM2_PATH}/"
  REMOTE_HASH="$(ssh -o StrictHostKeyChecking=no ${VM2_USER}@${VM2_HOST} "cd ${VM2_PATH} && sha256sum ${ARTIFACT_NAME} | awk '{print \$1}'" || true)"
  ssh -o StrictHostKeyChecking=no "${VM2_USER}@${VM2_HOST}" bash -c "'
    set -e
    cd \"${VM2_PATH}\"
    rm -rf dist
    tar -xzf \"${ARTIFACT_NAME}\"
    rm -f \"${ARTIFACT_NAME}\"
    if command -v pm2 >/dev/null 2>&1; then
      pm2 restart all || true
      pm2 save || true
    fi
  '"
fi

if command -v pm2 >/dev/null 2>&1; then
  pm2 startup systemd -u root --hp /root || true
fi

echo "=== UPDATE APP SERVER SELESAI ==="
