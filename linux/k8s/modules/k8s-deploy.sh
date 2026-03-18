#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

need_cmd mktemp

load_env_files
require_kubectl

K="$(kubectl_bin)"
NS="$(ns_name)"

OUT="$(bash "$DIR/k8s-render.sh")"

# Pre-flight Check: Pastikan image sudah ada di K3s ctr
echo "--> Memeriksa ketersediaan image di K3s..."
IMG_BE=$(backend_image)
IMG_FE=$(frontend_image)
CTR_LIST=$(as_root k3s ctr images ls | awk '{print $1}')

if ! echo "$CTR_LIST" | grep -qw "$IMG_BE"; then
  echo "[!] PERINGATAN: Image Backend ($IMG_BE) belum ada di K3s!"
  echo "    Silakan jalankan Menu 3 (Build Images) terlebih dahulu."
  exit 1
fi

if ! echo "$CTR_LIST" | grep -qw "$IMG_FE"; then
  echo "[!] PERINGATAN: Image Frontend ($IMG_FE) belum ada di K3s!"
  echo "    Deployment Frontend mungkin akan mengalami ErrImagePull."
  read -rp "    Tetap lanjut deploy? (y/n) [n]: " cont_deploy
  if [ "${cont_deploy,,}" != "y" ]; then
    exit 1
  fi
fi

echo "Applying manifests to namespace=$NS"
$K apply -R -f "$OUT"

# Bersihkan pod yang stuck ImagePullBackOff atau Error agar tidak mengganggu monitoring
echo "--> Membersihkan pod yang stuck (ImagePullBackOff/Error)..."
$K -n "$NS" delete pods --field-selector=status.phase=Failed >/dev/null 2>&1 || true
$K -n "$NS" get pods --no-headers | grep -E "ImagePullBackOff|ErrImagePull" | awk '{print $1}' | xargs -r $K -n "$NS" delete pod >/dev/null 2>&1 || true

echo "--> Menunggu pod menyala (Live Status)..."
# Jalankan status monitor di background selama rollout
(
  ITERATION=0
  MAX_ITERATION=20 # Sekitar 60 detik (20 * 3s)
  while [ $ITERATION -lt $MAX_ITERATION ]; do
    echo "--- [Status Pod @ $(date +%H:%M:%S)] ---"
    POD_STATUS=$($K -n "$NS" get pods --no-headers | grep -v "Completed")
    echo "$POD_STATUS" | head -n 10
    
    # Cek jika ada CrashLoopBackOff yang parah
    if echo "$POD_STATUS" | grep -q "CrashLoopBackOff"; then
       echo "   [!] Terdeteksi CrashLoopBackOff. Memeriksa log..."
       break
    fi

    # Cek jika sudah Running semua
    if ! echo "$POD_STATUS" | grep -qvE "Running|Terminating"; then
       echo "   [OK] Semua Pod sudah Running."
       break
    fi

    sleep 3
    ITERATION=$((ITERATION+1))
  done
) &
MONITOR_PID=$!

# Tunggu rollout selesai (ini akan memblokir sampai sukses atau timeout)
$K -n "$NS" rollout status deploy/backend-api --timeout=120s || {
  echo ""
  echo "!!! DEPLOY GAGAL ATAU TIMEOUT !!!"
  echo "Menampilkan penyebab error terakhir:"
  $K -n "$NS" get pods
  echo "--- Log Backend API ---"
  $K -n "$NS" logs deploy/backend-api --tail=30
}

# Matikan monitor background
kill $MONITOR_PID 2>/dev/null || true

echo "=== Verifikasi Networking K3s ==="
$K -n "$NS" get pods
$K -n "$NS" get svc

echo "Checking if NodePorts are active on host..."
FIX_RUN=false
for port in 32001 32080; do
  # Cek via ss (socket status) ATAU via iptables-save (lebih akurat untuk grep)
  if as_root ss -tulpn | grep -q ":$port " || as_root iptables-save | grep -qE "dpt:$port|--dport $port"; then
    echo "[OK] Port $port is active (ss/iptables)."
  else
    echo "[WARN] Port $port is NOT detected in networking rules."
    if [ "$FIX_RUN" = "false" ]; then
      echo "   [!] Mencoba memperbaiki konfigurasi networking K3s secara otomatis..."
      bash "$DIR/k8s-fix-network.sh"
      FIX_RUN=true
    fi
  fi
done

echo "Done"

