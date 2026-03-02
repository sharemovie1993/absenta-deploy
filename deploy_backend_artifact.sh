#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

APP_ROOT="${APP_ROOT:-/var/www/absenta}"
BACKEND_DIR="$APP_ROOT/backend"

echo "=== Deploy Backend Artifact (VM1 → VM2) ==="
echo "VM1 akan build backend, membuat artifact, mengirim ke VM2, lalu VM2 mengganti dist dan reload PM2."
echo ""

read -p "Host VM2 (contoh: vm2-app-absenta atau IP): " VM2_HOST_INPUT
VM2_HOST="${VM2_HOST_INPUT:-vm2-app-absenta}"
read -p "User VM2 (default root): " VM2_USER_INPUT
VM2_USER="${VM2_USER_INPUT:-root}"
read -p "Path backend di VM2 (default /var/www/absenta/backend): " VM2_PATH_INPUT
VM2_PATH="${VM2_PATH_INPUT:-/var/www/absenta/backend}"

ARTIFACT_NAME="backend.tar.gz"

command -v git >/dev/null 2>&1 || { echo "git tidak ditemukan"; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "npm tidak ditemukan"; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "tar tidak ditemukan"; exit 1; }
command -v scp >/dev/null 2>&1 || { echo "scp tidak ditemukan (install openssh-client)"; exit 1; }
command -v ssh >/dev/null 2>&1 || { echo "ssh tidak ditemukan (install openssh-client)"; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum tidak ditemukan"; exit 1; }

echo "Step 1 – Build backend di VM1"
cd "$APP_ROOT"
git pull || echo "git pull gagal, lanjutkan jika repo sudah up-to-date."
cd "$BACKEND_DIR"
npm install
npx prisma generate || true
npm run build

if [ ! -d "$BACKEND_DIR/dist" ]; then
  echo "Folder dist tidak ditemukan di $BACKEND_DIR"
  exit 1
fi

echo "Step 2 – Buat Artifact"
cd "$BACKEND_DIR"
rm -f "$ARTIFACT_NAME" || true
tar -czf "$ARTIFACT_NAME" dist package.json package-lock.json
LOCAL_HASH="$(sha256sum "$ARTIFACT_NAME" | awk '{print $1}')"
echo "SHA256 Artifact (VM1): $LOCAL_HASH"

echo "Step 3 – Kirim ke VM2"
scp -o StrictHostKeyChecking=no "$ARTIFACT_NAME" "${VM2_USER}@${VM2_HOST}:${VM2_PATH}/"

echo "Step 3.1 – Verifikasi hash di VM2"
REMOTE_HASH="$(ssh -o StrictHostKeyChecking=no ${VM2_USER}@${VM2_HOST} "cd ${VM2_PATH} && sha256sum ${ARTIFACT_NAME} | cut -d\\  -f1" || true)"
echo "SHA256 Artifact (VM2): $REMOTE_HASH"
if [ -z "$REMOTE_HASH" ]; then
  echo "Gagal membaca hash di VM2"
else
  if [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
    echo "PERINGATAN: Hash artifact berbeda antara VM1 dan VM2!"
    echo "Lanjut tetap dilakukan, namun disarankan periksa jaringan/SSH."
  fi
fi

echo "Step 4 – Extract dan reload di VM2"
ssh -o StrictHostKeyChecking=no "${VM2_USER}@${VM2_HOST}" bash -c "'
  set -e
  cd \"${VM2_PATH}\"
  # Safety: cek ruang disk minimal 100MB
  FREE_MB=\$(df -Pm \"${VM2_PATH}\" | tail -1 | tr -s \" \" | cut -d\" \" -f4)
  if [ \"\${FREE_MB}\" -lt 100 ]; then
    echo \"Ruang disk kurang dari 100MB, batalkan deploy.\"
    exit 1
  fi
  TS=\$(date +%Y%m%d%H%M%S)
  rm -rf release_tmp
  mkdir -p release_tmp
  tar -xzf \"${ARTIFACT_NAME}\" -C release_tmp
  # Validasi artifact
  if [ ! -d release_tmp/dist ]; then
    echo \"Artifact tidak berisi folder dist, batalkan.\"
    exit 1
  fi
  # Backup dan swap atomik
  if [ -d dist ]; then
    mv dist \"dist.bak_\${TS}\" || true
  fi
  mv release_tmp/dist dist
  rm -rf release_tmp
  rm -f \"${ARTIFACT_NAME}\"
  # Sinkronisasi dependency bila lock berubah atau node_modules belum ada
  NEED_INSTALL=false
  if [ -f package-lock.json ]; then
    REMOTE_LOCK_HASH=\$(sha256sum package-lock.json | cut -d\\  -f1)
    if [ -f package-lock.json.prev ]; then
        PREV_LOCK_HASH=\$(sha256sum package-lock.json.prev | cut -d\\  -f1)
    else
      PREV_LOCK_HASH=\"\"
    fi
    cp -f package-lock.json package-lock.json.prev || true
    if [ \"\$PREV_LOCK_HASH\" != \"\$REMOTE_LOCK_HASH\" ] || [ ! -d node_modules ]; then
      NEED_INSTALL=true
    fi
  else
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
    ROLLBACK=false
    if pm2 list | grep -q \"absenta-backend\"; then
      pm2 reload absenta-backend || ROLLBACK=true
    else
      pm2 start dist/main.js --name absenta-backend --node-args \"-r tsconfig-paths/register\" || ROLLBACK=true
    fi
    if [ \"\$ROLLBACK\" = true ] && [ -d \"dist.bak_\${TS}\" ]; then
      echo \"Reload gagal, rollback ke backup sebelumnya...\"
      rm -rf dist && mv \"dist.bak_\${TS}\" dist
      pm2 reload absenta-backend || true
    fi
    pm2 save || true
    # Verifikasi status proses PM2 (backend harus online)
    if pm2 list | grep -E "absenta-backend" | grep -qi "online"; then
      echo "PM2 absenta-backend online di VM2."
    else
      echo "PERINGATAN: PM2 absenta-backend tidak terlihat 'online'. Periksa log PM2."
      pm2 logs absenta-backend --lines 20 || true
    fi
  fi
  if command -v nginx >/dev/null 2>&1; then
    nginx -t && systemctl reload nginx || true
  fi
'"

echo "Selesai. Backend VM2 sekarang memakai artifact dari VM1."
