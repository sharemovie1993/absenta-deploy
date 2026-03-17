#!/usr/bin/env bash
set -euo pipefail

is_cmd() { command -v "$1" >/dev/null 2>&1; }
need_cmd() { is_cmd "$1" || { echo "Missing command: $1"; exit 1; }; }

SUDO_BIN="sudo"
if ! is_cmd sudo; then
  SUDO_BIN=""
fi

as_root() {
  if [ "$(id -u)" -eq 0 ] || [ -z "${SUDO_BIN}" ]; then
    "$@"
  else
    $SUDO_BIN "$@"
  fi
}

canonicalize_node_id() {
  printf '%s' "${1:-}" | tr -d '\r' | xargs | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:space:]_]+/-/g'
}

env_file_dir() {
  local dir
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  printf '%s' "$dir"
}

state_file() {
  printf '%s' "${ABSENTA_K8S_STATE_FILE:-/etc/absenta/k8s.env}"
}

load_env_files() {
  set -a
  local base
  base="$(env_file_dir)"
  [ -f "$(state_file)" ] && . "$(state_file)" || true
  [ -f "$base/../env/env.common" ] && . "$base/../env/env.common" || true
  [ -f "$base/../env/env.production" ] && . "$base/../env/env.production" || true
  [ -f "$base/../env/env.database" ] && . "$base/../env/env.database" || true
  [ -f "$base/../env/env.redis" ] && . "$base/../env/env.redis" || true
  [ -f "$base/../env/env.payment" ] && . "$base/../env/env.payment" || true
  [ -f "$base/../env/env.email" ] && . "$base/../env/env.email" || true
  set +a
}

save_state_kv() {
  local k="$1"
  local v="$2"
  local f
  f="$(state_file)"
  as_root mkdir -p "$(dirname "$f")" >/dev/null 2>&1 || true
  as_root touch "$f" >/dev/null 2>&1 || true
  as_root chmod 600 "$f" >/dev/null 2>&1 || true
  as_root bash -lc "grep -v '^${k}=' '$f' > '${f}.tmp' && printf '%s=%s\n' '$k' '$v' >> '${f}.tmp' && mv '${f}.tmp' '$f'"
}

kubectl_bin() {
  if is_cmd kubectl; then
    echo kubectl
    return
  fi
  if is_cmd k3s; then
    echo "k3s kubectl"
    return
  fi
  echo ""
}

require_kubectl() {
  local k
  k="$(kubectl_bin)"
  [ -n "$k" ] || { echo "kubectl not found (install k3s first)"; exit 1; }
}

ns_name() {
  printf '%s' "${ABSENTA_K8S_NAMESPACE:-absenta}"
}

backend_image() {
  printf '%s' "${ABSENTA_BACKEND_IMAGE:-absenta-backend:latest}"
}

frontend_image() {
  printf '%s' "${ABSENTA_FRONTEND_IMAGE:-absenta-frontend:latest}"
}

