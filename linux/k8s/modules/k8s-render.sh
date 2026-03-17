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

DEPLOY_FRONTEND="${K8S_DEPLOY_FRONTEND:-false}"
BACKEND_NODEPORT="${K8S_BACKEND_NODEPORT:-32001}"
FRONTEND_NODEPORT="${K8S_FRONTEND_NODEPORT:-32080}"

REPL_API="${K8S_REPL_API:-1}"
REPL_ATTENDANCE="${K8S_REPL_ATTENDANCE:-2}"
REPL_NOTIFICATION="${K8S_REPL_NOTIFICATION:-2}"
REPL_BILLING="${K8S_REPL_BILLING:-1}"
REPL_ANALYTICS="${K8S_REPL_ANALYTICS:-1}"
REPL_MAINTENANCE="${K8S_REPL_MAINTENANCE:-1}"
REPL_INFRA="${K8S_REPL_INFRA:-1}"

DATABASE_URL="${DATABASE_URL:-}"
REDIS_URL="${REDIS_URL:-}"
JWT_SECRET="${JWT_SECRET:-}"

[ -n "$DATABASE_URL" ] || { echo "DATABASE_URL is empty (set in ../env/env.database or /etc/absenta/k8s.env)"; exit 1; }
[ -n "$REDIS_URL" ] || { echo "REDIS_URL is empty (set in ../env/env.redis or /etc/absenta/k8s.env)"; exit 1; }
[ -n "$JWT_SECRET" ] || { echo "JWT_SECRET is empty (set in ../env/env.common)"; exit 1; }

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
  JWT_SECRET: $(b64 "$JWT_SECRET")
YAML

MAIN_DOMAIN="${MAIN_DOMAIN:-}"
PUBLIC_APP_URL="${PUBLIC_APP_URL:-}"
PUBLIC_INVOICE_BASE_URL="${PUBLIC_INVOICE_BASE_URL:-}"
CACHE_TTL_DEFAULT="${CACHE_TTL_DEFAULT:-300}"

cat > "$OUT_DIR/02-config.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: absenta-config
  namespace: ${NAMESPACE}
data:
  MAIN_DOMAIN: "${MAIN_DOMAIN}"
  PUBLIC_APP_URL: "${PUBLIC_APP_URL}"
  PUBLIC_INVOICE_BASE_URL: "${PUBLIC_INVOICE_BASE_URL}"
  CACHE_TTL_DEFAULT: "${CACHE_TTL_DEFAULT}"
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
      nodePort: ${BACKEND_NODEPORT}
YAML

if [ "${DEPLOY_FRONTEND,,}" = "true" ]; then
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
      labels:
        app: frontend
    spec:
      containers:
        - name: web
          image: ${FRONTEND_IMAGE}
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8080
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
      port: 8080
      targetPort: 8080
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

