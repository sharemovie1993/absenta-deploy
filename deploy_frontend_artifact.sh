#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

APP_ROOT="${APP_ROOT:-/var/www/absenta}"
FRONTEND_DIR="$APP_ROOT/frontend"

echo "=== Deploy Frontend Artifact (VM1 → VM2) ==="
echo "VM1 akan melakukan build, membuat artifact, mengirim ke VM2, lalu VM2 mengganti dist dan restart PM2."
echo ""

read -p "Host VM2 (contoh: vm2-app-absenta atau IP): " VM2_HOST_INPUT
VM2_HOST="${VM2_HOST_INPUT:-vm2-app-absenta}"
read -p "User VM2 (default root): " VM2_USER_INPUT
VM2_USER="${VM2_USER_INPUT:-root}"
read -p "Path frontend di VM2 (default /var/www/absenta/frontend): " VM2_PATH_INPUT
VM2_PATH="${VM2_PATH_INPUT:-/var/www/absenta/frontend}"

ARTIFACT_NAME="frontend.tar.gz"

command -v git >/dev/null 2>&1 || { echo "git tidak ditemukan"; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "npm tidak ditemukan"; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "tar tidak ditemukan"; exit 1; }
command -v scp >/dev/null 2>&1 || { echo "scp tidak ditemukan (install openssh-client)"; exit 1; }
command -v ssh >/dev/null 2>&1 || { echo "ssh tidak ditemukan (install openssh-client)"; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum tidak ditemukan"; exit 1; }

echo "Step 1 – Build di VM1"
cd "$APP_ROOT"
git pull || echo "git pull gagal, lanjutkan jika repo sudah up-to-date."
cd "$FRONTEND_DIR"
npm install
npm run build

if [ ! -d "$FRONTEND_DIR/dist" ]; then
  echo "Folder dist tidak ditemukan di $FRONTEND_DIR"
  exit 1
fi

echo "Step 2 – Buat Artifact"
cd "$FRONTEND_DIR"
rm -f "$ARTIFACT_NAME" || true
tar -czf "$ARTIFACT_NAME" dist
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

echo "Step 4 – Extract dan restart di VM2"
read -p "Salin .env frontend ke VM2? (y/N): " COPY_FE_ENV_INPUT
COPY_FE_ENV="${COPY_FE_ENV_INPUT:-N}"
if [ "$COPY_FE_ENV" = "y" ] || [ "$COPY_FE_ENV" = "Y" ]; then
  if [ -f "$FRONTEND_DIR/.env" ]; then
    scp -o StrictHostKeyChecking=no "$FRONTEND_DIR/.env" "${VM2_USER}@${VM2_HOST}:${VM2_PATH}/.env"
  fi
fi
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
  if [ ! -f release_tmp/dist/index.html ]; then
    echo \"Artifact tidak berisi dist/index.html, batalkan.\"
    exit 1
  fi
  if ! ls release_tmp/dist/assets/*.js >/dev/null 2>&1; then
    echo \"Folder assets tidak berisi bundle .js, batalkan.\"
    exit 1
  fi
  # Backup dan swap atomik
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
  if command -v nginx >/dev/null 2>&1; then
    nginx -t && systemctl reload nginx || true
  fi
'"

echo "Selesai. Frontend VM2 sekarang memakai artifact dari VM1."
