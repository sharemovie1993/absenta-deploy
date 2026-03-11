#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$DIR/docker-compose.linux.yml"

# -----------------------------------------------------------------------------
# Ensure dependencies (Ubuntu 22.x friendly). Skip if already installed.
# -----------------------------------------------------------------------------
is_cmd() { command -v "$1" >/dev/null 2>&1; }

apt_update_done=""
apt_ensure() {
  if ! dpkg -s "$1" >/dev/null 2>&1; then
    if [ -z "${apt_update_done}" ]; then
      sudo apt-get update -y
      apt_update_done="yes"
    fi
    sudo apt-get install -y "$@"
  fi
}

ensure_prereqs() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release || true
  fi
  if [ "${ID:-}" = "ubuntu" ]; then
    apt_ensure ca-certificates
    apt_ensure curl
    apt_ensure gnupg
    apt_ensure lsb-release
  fi
}

ensure_docker() {
  if is_cmd docker; then
    return 0
  fi
  if [ "${ID:-}" = "ubuntu" ]; then
    sudo install -m 0755 -d /etc/apt/keyrings
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      sudo chmod a+r /etc/apt/keyrings/docker.gpg
    fi
    codename="$(. /etc/os-release && echo "$UBUNTU_CODENAME")"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    if systemctl >/dev/null 2>&1; then
      sudo systemctl enable --now docker || true
    fi
  else
    echo "Unsupported distro for auto-install. Please install Docker manually."
  fi
}

ensure_prereqs
ensure_docker

# Use sudo for docker if current user lacks access to Docker daemon
DOCKER_BIN="docker"
if ! docker info >/dev/null 2>&1; then
  if is_cmd sudo && sudo -n true 2>/dev/null; then
    DOCKER_BIN="sudo docker"
  fi
fi
max_wait=180
waited=0
until docker info >/dev/null 2>&1; do
until $DOCKER_BIN info >/dev/null 2>&1; do
  waited=$((waited+5))
  if [ "$waited" -ge "$max_wait" ]; then
    echo "docker engine not ready"
    break
  fi
done
docker compose -f "$COMPOSE_FILE" down || true
$DOCKER_BIN compose -f "$COMPOSE_FILE" down || true
$DOCKER_BIN compose -f "$COMPOSE_FILE" build --no-cache
$DOCKER_BIN compose -f "$COMPOSE_FILE" up -d --remove-orphans
$DOCKER_BIN ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

env_dir="$DIR/../env"
tmp_env="/tmp/absenta-worker-env-node-attendance.env"
cat "$env_dir/env.common" "$env_dir/env.database" "$env_dir/env.redis" "$env_dir/env.production" > "$tmp_env" || true
echo "NODE_NAME=node-attendance" >> "$tmp_env"

ensure_standby() {
  local name="$1"
  local node_name="$2"
  local script="$3"
  if $DOCKER_BIN ps -a --format "{{.Names}}" | grep -q "^${name}\$" 2>/dev/null; then
    $DOCKER_BIN stop "$name" >/dev/null 2>&1 || true
    return 0
  fi
  local tmp="/tmp/absenta-worker-env-${node_name}.env"
  cat "$env_dir/env.common" "$env_dir/env.database" "$env_dir/env.redis" "$env_dir/env.production" > "$tmp" || true
  echo "NODE_NAME=${node_name}" >> "$tmp"
  $DOCKER_BIN create --name "$name" --restart unless-stopped --network absenta-net --env-file "$tmp" absenta-backend:latest node "$script" >/dev/null 2>&1 || true
}

ensure_standby "absenta-worker-attendance-2" "node-attendance" "dist/workers/attendance.worker.js"
ensure_standby "absenta-worker-attendance-3" "node-attendance" "dist/workers/attendance.worker.js"
ensure_standby "absenta-worker-attendance-4" "node-attendance" "dist/workers/attendance.worker.js"
ensure_standby "absenta-worker-billing-2" "node-billing" "dist/workers/billing.worker.js"
ensure_standby "absenta-worker-notification-2" "node-billing" "dist/workers/notification.worker.js"
exited="$($DOCKER_BIN ps -a --filter "status=exited" --format "{{.Names}}" || true)"
  for n in $exited; do
    echo "==== LOG: $n ===="
    docker logs "$n" || true
    $DOCKER_BIN logs "$n" || true
  done
fi
if command -v curl >/dev/null 2>&1; then
  curl -s -o /dev/null -w "health http %{http_code}\n" http://localhost:3001/health || true
fi
exit 0
exit 0
