#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

need_cmd base64
need_cmd mktemp

load_env_files
require_kubectl

NAMESPACE="$(ns_name)"
BACKEND_IMAGE="$(backend_image)"
FRONTEND_IMAGE="$(frontend_image)"

# Jika frontend image sudah pernah di-build/import, default ke true
if as_root k3s ctr images ls | grep -q "$FRONTEND_IMAGE"; then
  DEPLOY_FRONTEND="${K8S_DEPLOY_FRONTEND:-true}"
else
  DEPLOY_FRONTEND="${K8S_DEPLOY_FRONTEND:-false}"
fi
BACKEND_NODEPORT="${K8S_BACKEND_NODEPORT:-32001}"
FRONTEND_NODEPORT="${K8S_FRONTEND_NODEPORT:-32080}"

REPL_API="${K8S_REPL_API:-1}"
REPL_ATTENDANCE="${K8S_REPL_ATTENDANCE:-2}"
REPL_NOTIFICATION="${K8S_REPL_NOTIFICATION:-2}"
REPL_BILLING="${K8S_REPL_BILLING:-1}"
REPL_ANALYTICS="${K8S_REPL_ANALYTICS:-1}"
REPL_MAINTENANCE="${K8S_REPL_MAINTENANCE:-1}"
REPL_INFRA="${K8S_REPL_INFRA:-1}"

# Ambil semua variabel penting dari env files
NODE_ENV="${NODE_ENV:-production}"
NODE_ID="${NODE_ID:-node-1}"
APP_VERSION="${APP_VERSION:-1.0.0}"
WORKER_VERSION="${WORKER_VERSION:-1.0.0}"
MAIN_DOMAIN="${MAIN_DOMAIN:-}"
PUBLIC_APP_URL="${PUBLIC_APP_URL:-}"
PUBLIC_INVOICE_BASE_URL="${PUBLIC_INVOICE_BASE_URL:-}"
STORAGE_DRIVER="${STORAGE_DRIVER:-s3}"
S3_ENDPOINT="${S3_ENDPOINT:-}"
S3_BUCKET="${S3_BUCKET:-absenta-storage}"
S3_REGION="${S3_REGION:-us-east-1}"
S3_ACCESS_KEY="${S3_ACCESS_KEY:-}"
S3_SECRET_KEY="${S3_SECRET_KEY:-}"
S3_FORCE_PATH_STYLE="${S3_FORCE_PATH_STYLE:-true}"
S3_PUBLIC_BASE_URL="${S3_PUBLIC_BASE_URL:-}"

DATABASE_URL="${DATABASE_URL:-}"
REDIS_MODE="${REDIS_MODE:-single}"
REDIS_URL="${REDIS_URL:-}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
JWT_SECRET="${JWT_SECRET:-}"

[ -n "$DATABASE_URL" ] || { echo "DATABASE_URL is empty"; exit 1; }
[ -n "$REDIS_URL" ] || { echo "REDIS_URL is empty"; exit 1; }
[ -n "$JWT_SECRET" ] || { echo "JWT_SECRET is empty"; exit 1; }

b64() { printf '%s' "$1" | base64 | tr -d '\n'; }

OUT_DIR="${1:-}"
if [ -z "$OUT_DIR" ]; then
  OUT_DIR="$(mktemp -d)"
fi

mkdir -p "$OUT_DIR"

cat > "$OUT_DIR/00-namespace.yaml" <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
YAML

cat > "$OUT_DIR/01-secrets.yaml" <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: absenta-secrets
  namespace: ${NAMESPACE}
type: Opaque
data:
  DATABASE_URL: $(b64 "$DATABASE_URL")
  REDIS_URL: $(b64 "$REDIS_URL")
  REDIS_PASSWORD: $(b64 "$REDIS_PASSWORD")
  JWT_SECRET: $(b64 "$JWT_SECRET")
  S3_ACCESS_KEY: $(b64 "$S3_ACCESS_KEY")
  S3_SECRET_KEY: $(b64 "$S3_SECRET_KEY")
YAML

cat > "$OUT_DIR/02-config.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: absenta-config
  namespace: ${NAMESPACE}
data:
  NODE_ENV: "${NODE_ENV}"
  NODE_ID: "${NODE_ID}"
  APP_VERSION: "${APP_VERSION}"
  WORKER_VERSION: "${WORKER_VERSION}"
  MAIN_DOMAIN: "${MAIN_DOMAIN}"
  PUBLIC_APP_URL: "${PUBLIC_APP_URL}"
  PUBLIC_INVOICE_BASE_URL: "${PUBLIC_INVOICE_BASE_URL}"
  REDIS_MODE: "${REDIS_MODE}"
  STORAGE_DRIVER: "${STORAGE_DRIVER}"
  S3_ENDPOINT: "${S3_ENDPOINT}"
  S3_BUCKET: "${S3_BUCKET}"
  S3_REGION: "${S3_REGION}"
  S3_FORCE_PATH_STYLE: "${S3_FORCE_PATH_STYLE}"
  S3_PUBLIC_BASE_URL: "${S3_PUBLIC_BASE_URL}"
  EMBEDDED_WORKERS: "false"
  PM2_DISABLED: "true"
YAML

cat > "$OUT_DIR/10-backend-api.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-api
  namespace: ${NAMESPACE}
spec:
  replicas: ${REPL_API}
  selector:
    matchLabels:
      app: backend-api
  template:
    metadata:
      annotations:
        absenta.deploy/timestamp: "${TS:-$(date +%s)}"
      labels:
        app: backend-api
    spec:
      containers:
        - name: api
          image: ${BACKEND_IMAGE}
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 3001
          env:
            - name: NODE_NAME
              value: "node-api"
          envFrom:
            - secretRef:
                name: absenta-secrets
            - configMapRef:
                name: absenta-config
---
apiVersion: v1
kind: Service
metadata:
  name: backend-api
  namespace: ${NAMESPACE}
spec:
  type: NodePort
  selector:
    app: backend-api
  ports:
    - name: http
      port: 3001
      targetPort: 3001
      protocol: TCP
      nodePort: ${BACKEND_NODEPORT}
YAML

if [ "${DEPLOY_FRONTEND,,}" = "true" ]; then
  # Tambahkan timestamp ke annotation agar pod selalu di-refresh (mencegah ImagePullBackOff pod lama)
  TS=$(date +%s)
  cat > "$OUT_DIR/11-frontend.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      annotations:
        absenta.deploy/timestamp: "${TS}"
      labels:
        app: frontend
    spec:
      containers:
        - name: web
          image: ${FRONTEND_IMAGE}
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: ${NAMESPACE}
spec:
  type: NodePort
  selector:
    app: frontend
  ports:
    - name: http
      port: 80
      targetPort: 80
      protocol: TCP
      nodePort: ${FRONTEND_NODEPORT}
YAML
fi

emit_worker() {
  local name="$1"
  local replicas="$2"
  local node_name="$3"
  local cmd="$4"
  cat > "$OUT_DIR/20-worker-${name}.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker-${name}
  namespace: ${NAMESPACE}
spec:
  replicas: ${replicas}
  selector:
    matchLabels:
      app: worker-${name}
  template:
    metadata:
      labels:
        app: worker-${name}
    spec:
      containers:
        - name: worker
          image: ${BACKEND_IMAGE}
          imagePullPolicy: IfNotPresent
          command: ["node","${cmd}"]
          env:
            - name: NODE_NAME
              value: "${node_name}"
          envFrom:
            - secretRef:
                name: absenta-secrets
            - configMapRef:
                name: absenta-config
YAML
}

emit_worker "attendance" "$REPL_ATTENDANCE" "node-attendance" "dist/workers/attendance.worker.js"
emit_worker "notification" "$REPL_NOTIFICATION" "node-notification" "dist/workers/notification.worker.js"
emit_worker "billing" "$REPL_BILLING" "node-billing" "dist/workers/billing.worker.js"
emit_worker "analytics" "$REPL_ANALYTICS" "node-analytics" "dist/workers/analytics.worker.js"
emit_worker "maintenance" "$REPL_MAINTENANCE" "node-maintenance" "dist/workers/maintenance.worker.js"
emit_worker "infra" "$REPL_INFRA" "node-infra" "dist/workers/infra.worker.js"

echo "$OUT_DIR"

