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
# Tambahkan loop untuk memastikan pod sudah bukan ContainerCreating lagi
for i in {1..20}; do
  PHASE=$($K -n "$NS" get pods -l "job-name=$name" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
  REASON=$($K -n "$NS" get pods -l "job-name=$name" -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || echo "")
  
  if [ "$PHASE" = "Running" ] || [ "$PHASE" = "Succeeded" ] || [ "$PHASE" = "Failed" ]; then
    break
  fi
  
  echo "    ... Status: $PHASE ($REASON) - Menunggu kontainer siap ($i/20)"
  sleep 3
done

# Ambil nama pod secara spesifik
POD_NAME=$($K -n "$NS" get pods -l "job-name=$name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$POD_NAME" ]; then
  echo "--> Mengambil log dari pod: $POD_NAME"
  # Cek sekali lagi apakah sudah bisa ditarik lognya
  $K -n "$NS" logs -f "$POD_NAME" || {
    echo "[!] Streaming terputus, mengambil log statis..."
    sleep 2
    $K -n "$NS" logs "$POD_NAME"
  }
else
  echo "[!] Pod tidak ditemukan, menampilkan log Job..."
  $K -n "$NS" logs job/"$name"
fi
echo "-----------------------------------------------"

echo "--> Memeriksa status akhir job..."
# Tunggu sebentar agar Kubernetes mengupdate status job
SUCCESS=false
for j in {1..5}; do
  if $K -n "$NS" get job "$name" -o jsonpath='{.status.succeeded}' 2>/dev/null | grep -q "1"; then
    echo "[OK] $name berhasil diselesaikan."
    SUCCESS=true
    break
  fi
  sleep 2
done

if [ "$SUCCESS" = "false" ]; then
  echo "[!] $name GAGAL atau status belum terupdate."
  # ... rest of the error detection ...
  # Deteksi error P3009 dari log pod
  if $K -n "$NS" logs "$POD_NAME" 2>/dev/null | grep -q "P3009"; then
    FAILED_MIGRATION=$($K -n "$NS" logs "$POD_NAME" | grep -oP 'The \K[a-zA-Z0-9_]+(?= migration started)' | head -n1 || echo "")
    if [ -n "$FAILED_MIGRATION" ]; then
      echo "    [DETEKSI] Ditemukan migrasi yang gagal sebelumnya: $FAILED_MIGRATION"
      read -rp "    [?] Apakah Bapak ingin saya melakukan 'migrate resolve' untuk mengabaikan status gagal ini? (y/n) [n]: " resolve_ans
      if [ "${resolve_ans,,}" = "y" ]; then
        echo "    --> Mencoba melakukan resolve pada migrasi: $FAILED_MIGRATION"
        run_job "prisma-resolve-job" "npx prisma migrate resolve --applied $FAILED_MIGRATION"
        echo "    --> Selesai. Silakan jalankan kembali Menu 5 untuk melanjutkan migrasi utama."
        exit 0
      fi
    fi
  fi
  exit 1
fi
  
  echo "--> Log dari $name:"
  $K -n "$NS" logs job/"$name"
  
  # Bersihkan job setelah selesai
  $K -n "$NS" delete job "$name" >/dev/null 2>&1
}

# 1. Main Migration Job
run_job "prisma-migrate-job" "npx prisma migrate deploy"

# 2. Check for P3009 Error and Auto-Resolve
if [ $? -ne 0 ]; then
  echo "--> Mendeteksi kegagalan migrasi. Memeriksa detail error..."
  # Ambil nama pod terakhir
  LAST_POD=$($K -n "$NS" get pods -l "job-name=prisma-migrate-job" --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || echo "")
  
  if [ -n "$LAST_POD" ] && $K -n "$NS" logs "$LAST_POD" 2>/dev/null | grep -q "P3009"; then
    FAILED_MIG=$( $K -n "$NS" logs "$LAST_POD" | grep -oP 'The \K[a-zA-Z0-9_]+(?= migration started)' | head -n1 || echo "" )
    if [ -n "$FAILED_MIG" ]; then
      echo "    [!] Terdeteksi Error P3009 pada migrasi: $FAILED_MIG"
      echo "    --> Menjalankan 'prisma migrate resolve' secara otomatis untuk membersihkan status..."
      run_job "prisma-resolve-job" "npx prisma migrate resolve --applied $FAILED_MIG"
      
      echo "    --> Status dibersihkan. Mencoba kembali migrasi utama..."
      run_job "prisma-migrate-job-retry" "npx prisma migrate deploy"
    fi
  fi
fi

# 3. Seed Job
run_job "prisma-seed-job" "npm run seed"

echo "=== Done ==="
