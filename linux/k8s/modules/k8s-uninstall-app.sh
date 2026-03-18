#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

load_env_files
require_kubectl

K="$(kubectl_bin)"
NS="$(ns_name)"

echo "Menghapus namespace: $NS"
# Gunakan delete tanpa wait agar kita bisa pantau manual
$K delete ns "$NS" --wait=false >/dev/null 2>&1 || true

echo "--> Menunggu namespace benar-benar terhapus (Kubernetes sedang membersihkan pod/svc)..."
ITER=0
MAX_ITER=30 # 60 detik total
while $K get ns "$NS" >/dev/null 2>&1; do
  if [ $ITER -eq $MAX_ITER ]; then
    echo ""
    echo "[!] Peringatan: Namespace masih ada setelah 60 detik."
    echo "    Ini biasanya karena ada pod yang stuck. Mencoba paksa..."
    # Hapus pod yang tersisa dengan force
    $K -n "$NS" delete pods --all --force --grace-period=0 >/dev/null 2>&1 || true
    break
  fi
  
  echo -n "."
  sleep 2
  ITER=$((ITER+1))
done

echo ""
echo "OK: Namespace $NS sudah bersih."

