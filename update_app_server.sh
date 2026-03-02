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
  read -p "Salin .env backend ke VM2? (y/N): " COPY_ENV_INPUT
  COPY_ENV="${COPY_ENV_INPUT:-N}"
  if [ "$COPY_ENV" = "y" ] || [ "$COPY_ENV" = "Y" ]; then
    if [ -f "$BACKEND_DIR/.env" ]; then
      scp -o StrictHostKeyChecking=no "$BACKEND_DIR/.env" "${VM2_BACKEND_USER}@${VM2_BACKEND_HOST}:${VM2_BACKEND_PATH}/.env"
      SVC_PATH="$(grep -E '^FIREBASE_SERVICE_ACCOUNT_PATH=' "$BACKEND_DIR/.env" | sed 's/^FIREBASE_SERVICE_ACCOUNT_PATH=//; s/\"//g')"
      if [ -n "$SVC_PATH" ] && [ -f "$SVC_PATH" ]; then
        ssh -o StrictHostKeyChecking=no "${VM2_BACKEND_USER}@${VM2_BACKEND_HOST}" "mkdir -p \"$(dirname "$SVC_PATH")\""
        scp -o StrictHostKeyChecking=no "$SVC_PATH" "${VM2_BACKEND_USER}@${VM2_BACKEND_HOST}:$SVC_PATH"
      fi
    fi
  fi
  ssh -o StrictHostKeyChecking=no "${VM2_BACKEND_USER}@${VM2_BACKEND_HOST}" bash -c "'
    set -e
    cd \"${VM2_BACKEND_PATH}\"
    FREE_MB=\$(df -Pm \"${VM2_BACKEND_PATH}\" | tail -1 | tr -s \" \" | cut -d\" \" -f4)
    if [ \"\${FREE_MB}\" -lt 100 ]; then
      echo \"Ruang disk kurang dari 100MB, batalkan deploy.\"
      exit 1
    fi
    TS=\$(date +%Y%m%d%H%M%S)
    rm -rf release_tmp
    mkdir -p release_tmp
    tar -xzf \"${BACKEND_ARTIFACT}\" -C release_tmp
    if [ ! -d release_tmp/dist ]; then
      echo \"Artifact tidak berisi folder dist, batalkan.\"
      exit 1
    fi
    if [ -d dist ]; then
      mv dist \"dist.bak_\${TS}\" || true
    fi
    mv release_tmp/dist dist
    rm -rf release_tmp
    rm -f \"${BACKEND_ARTIFACT}\"
    # Jika package-lock.json berubah, jalankan npm ci --omit=dev dan prisma generate
    NEED_INSTALL=false
    if [ -f package-lock.json ]; then
      REMOTE_LOCK_HASH=\$(sha256sum package-lock.json | cut -d\\  -f1)
      # Simpan hash lama jika ada
      if [ -f package-lock.json.prev ]; then
        PREV_LOCK_HASH=\$(sha256sum package-lock.json.prev | cut -d\\  -f1)
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
    if [ \"\$NEED_INSTALL\" = true ] && command -v npm >/dev/null 2>&1; then
      npm ci --omit=dev || npm install --omit=dev
    fi
    # Safety: selalu generate Prisma client setelah swap dist
    if command -v npx >/dev/null 2>&1; then
      npx prisma generate || true
    fi
    # Safety: pastikan .env ada
    if [ ! -f .env ]; then
      echo \".env backend tidak ditemukan di ${VM2_BACKEND_PATH}. Deploy dibatalkan.\"
      exit 1
    fi
    if command -v pm2 >/dev/null 2>&1; then
      ROLLBACK=false
      if pm2 list | grep -q \"absenta-backend\"; then
        pm2 reload absenta-backend || pm2 restart absenta-backend || ROLLBACK=true
      else
        pm2 start dist/main.js --name absenta-backend --node-args \"-r tsconfig-paths/register\" || ROLLBACK=true
      fi
      if [ \"\$ROLLBACK\" = true ] && [ -d \"dist.bak_\${TS}\" ]; then
        echo \"Reload gagal, rollback ke backup sebelumnya...\"
        rm -rf dist && mv \"dist.bak_\${TS}\" dist
        pm2 reload absenta-backend || true
      fi
      pm2 save || true
      if pm2 list | grep -E \"absenta-backend\" | grep -qi \"online\"; then
        echo \"PM2 absenta-backend online di VM2.\"
      else
        echo \"PERINGATAN: PM2 absenta-backend tidak terlihat 'online'. Periksa log PM2.\"
        pm2 logs absenta-backend --lines 20 || true
      fi
    fi
    if command -v nginx >/dev/null 2>&1; then
      nginx -t && systemctl reload nginx || true
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
  REMOTE_HASH="$(ssh -o StrictHostKeyChecking=no ${VM2_USER}@${VM2_HOST} "cd ${VM2_PATH} && sha256sum ${ARTIFACT_NAME} | cut -d\\  -f1" || true)"
  ssh -o StrictHostKeyChecking=no "${VM2_USER}@${VM2_HOST}" bash -c "'
    set -e
    cd \"${VM2_PATH}\"
    FREE_MB=\$(df -Pm \"${VM2_PATH}\" | tail -1 | tr -s \" \" | cut -d\" \" -f4)
    if [ \"\${FREE_MB}\" -lt 100 ]; then
      echo \"Ruang disk kurang dari 100MB, batalkan deploy.\"
      exit 1
    fi
    TS=\$(date +%Y%m%d%H%M%S)
    rm -rf release_tmp
    mkdir -p release_tmp
    tar -xzf \"${ARTIFACT_NAME}\" -C release_tmp
    if [ ! -f release_tmp/dist/index.html ]; then
      echo \"Artifact tidak berisi dist/index.html, batalkan.\"
      exit 1
    fi
    if ! ls release_tmp/dist/assets/*.js >/dev/null 2>&1; then
      echo \"Folder assets tidak berisi bundle .js, batalkan.\"
      exit 1
    fi
    if [ -d dist ]; then
      mv dist \"dist.bak_\${TS}\" || true
    fi
    mv release_tmp/dist dist
    rm -rf release_tmp
    rm -f \"${ARTIFACT_NAME}\"
    if command -v pm2 >/dev/null 2>&1; then
      pm2 restart all || true
      pm2 save || true
      # Verifikasi status proses PM2 (frontend harus online)
      if pm2 list | grep -E "absenta-frontend" | grep -qi "online"; then
        echo "PM2 absenta-frontend online di VM2."
      else
        echo "PM2 absenta-frontend belum online, mencoba start..."
        pm2 start "serve -s dist -l 8080" --name absenta-frontend || true
        pm2 save || true
        if pm2 list | grep -E "absenta-frontend" | grep -qi "online"; then
          echo "PM2 absenta-frontend berhasil online."
        else
          echo "PERINGATAN: PM2 absenta-frontend tidak terlihat 'online'. Periksa log PM2."
          pm2 logs absenta-frontend --lines 20 || true
        fi
      fi
    fi
  '"
fi

if command -v pm2 >/dev/null 2>&1; then
  pm2 startup systemd -u root --hp /root || true
fi

echo "=== UPDATE APP SERVER SELESAI ==="
