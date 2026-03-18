#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

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

# Background monitor
(
  while true; do
    clear
    echo "--- [Status Pod @ $(date +%H:%M:%S)] ---"
    $K -n "$NS" get pods
    
    # Cek jika ada CrashLoopBackOff
    if $K -n "$NS" get pods | grep -q "CrashLoopBackOff"; then
       CRASH_POD=$($K -n "$NS" get pods | grep "CrashLoopBackOff" | awk '{print $1}' | head -n1)
       echo ""
       echo "[!] Terdeteksi Crash pada pod: $CRASH_POD"
       echo "--- Log Terakhir ---"
       $K -n "$NS" logs "$CRASH_POD" --tail=20
       break
    fi
    
    # Cek jika semua sudah Running
    TOTAL=$($K -n "$NS" get pods --no-headers | wc -l)
    READY=$($K -n "$NS" get pods --no-headers | grep "1/1" | wc -l)
    READY_2=$($K -n "$NS" get pods --no-headers | grep "2/2" | wc -l)
    SUM=$((READY + READY_2))
    
    if [ "$SUM" -eq "$TOTAL" ] && [ "$TOTAL" -gt 0 ]; then
       echo ""
       echo "[OK] Semua pod sudah menyala sempurna!"
       break
    fi
    
    sleep 3
  done
) &
MONITOR_PID=$!

# Wait for rollout
$K -n "$NS" rollout status deployment/backend-api --timeout=300s || true

# Matikan monitor background
kill $MONITOR_PID 2>/dev/null || true

echo ""
echo "=== Rangkaian Akhir: Database Migration & Seed ==="
# Jalankan migrasi secara otomatis sebagai bagian dari deploy
bash "$DIR/k8s-migrate.sh"

echo ""
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
