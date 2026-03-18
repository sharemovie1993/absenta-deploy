#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

load_env_files
require_kubectl

K="$(kubectl_bin)"
NS="$(ns_name)"
IMAGE="$(backend_image)"

echo "=== Prisma Migration & Seed (K8s) ==="

run_job() {
  local name="$1"
  local cmd="$2"
  
  echo "--> Menjalankan $name..."
$K -n "$NS" delete job "$name" >/dev/null 2>&1 || true

cat <<EOF | $K apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: $name
  namespace: $NS
spec:
  template:
    spec:
      containers:
      - name: job
        image: $IMAGE
        imagePullPolicy: IfNotPresent
        command: ["sh", "-c", "$cmd"]
        envFrom:
        - secretRef:
            name: absenta-secrets
        - configMapRef:
            name: absenta-config
      restartPolicy: Never
  backoffLimit: 0
EOF

echo "--> Streaming log dari $name (Real-time)..."
echo "-----------------------------------------------"
# Tunggu pod sampai benar-benar menyala (Running/Succeeded/Failed)
echo "--> Menunggu pod migrasi menyala..."
$K -n "$NS" wait --for=condition=Ready pod -l "job-name=$name" --timeout=60s >/dev/null 2>&1 || true

# Ambil nama pod secara spesifik
POD_NAME=$($K -n "$NS" get pods -l "job-name=$name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$POD_NAME" ]; then
  echo "--> Mengambil log dari pod: $POD_NAME"
  # Gunakan logs -f tapi beri sedikit jeda agar kontainer benar-benar start
  sleep 1
  $K -n "$NS" logs -f "$POD_NAME" || {
    echo "[!] Streaming terputus, mengambil log statis..."
    $K -n "$NS" logs "$POD_NAME"
  }
else
  echo "[!] Pod tidak ditemukan, menampilkan log Job..."
  $K -n "$NS" logs job/"$name"
fi
echo "-----------------------------------------------"

echo "--> Memeriksa status akhir job..."
if $K -n "$NS" get job "$name" -o jsonpath='{.status.succeeded}' | grep -q "1"; then
  echo "[OK] $name berhasil diselesaikan."
else
  echo "[!] $name GAGAL. Silakan cek detail di atas."
  exit 1
fi
  
  echo "--> Log dari $name:"
  $K -n "$NS" logs job/"$name"
  
  # Bersihkan job setelah selesai
  $K -n "$NS" delete job "$name" >/dev/null 2>&1
}

run_job "prisma-migrate-job" "npx prisma migrate deploy"
run_job "prisma-seed-job" "npm run seed"

echo "=== Done ==="
