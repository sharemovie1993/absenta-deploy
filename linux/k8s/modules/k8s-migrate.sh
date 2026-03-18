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
  
  # Hapus job lama jika ada
  $K -n "$NS" delete job "$name" --ignore-not-found >/dev/null 2>&1

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
        command: ["sh", "-c", "echo 'DEBUG: Current Dir:' && pwd && echo 'DEBUG: Prisma Files:' && ls -R prisma && $cmd"]
        envFrom:
        - secretRef:
            name: absenta-secrets
        - configMapRef:
            name: absenta-config
      restartPolicy: Never
  backoffLimit: 0
EOF

  echo "--> Menunggu $name selesai..."
  $K -n "$NS" wait --for=condition=complete job/"$name" --timeout=300s || {
    echo "Kesalahan: $name gagal atau timeout."
    $K -n "$NS" logs job/"$name"
    exit 1
  }
  
  echo "--> Log dari $name:"
  $K -n "$NS" logs job/"$name"
  
  # Bersihkan job setelah selesai
  $K -n "$NS" delete job "$name" >/dev/null 2>&1
}

run_job "prisma-migrate-job" "npx prisma migrate deploy"
run_job "prisma-seed-job" "npm run seed"

echo "=== Done ==="
