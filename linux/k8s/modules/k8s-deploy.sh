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

echo "Applying manifests to namespace=$NS"
$K apply -R -f "$OUT"

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

# Detect WireGuard IP (e.g., 10.60.0.1)
WG_INTERFACE="${WG_INTERFACE:-wg0}"
WG_IP=$(ip -4 addr show "$WG_INTERFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "")

echo "Checking if NodePorts are listening on host..."
FIX_RUN=false
for port in 32001 32080; do
  if as_root ss -tulpn | grep -q ":$port "; then
    echo "[OK] Port $port is listening on host."
  else
    echo "[WARN] Port $port is NOT listening on host."
    if [ "$FIX_RUN" = "false" ]; then
      echo "   [!] Mencoba memperbaiki konfigurasi networking K3s secara otomatis..."
      bash "$DIR/k8s-fix-network.sh"
      FIX_RUN=true
    fi
  fi
done

echo "Done"

