#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$DIR/docker-compose.linux.yml}"
if [ -z "${BACKEND_PATH:-}" ]; then
  legacy_backend="$DIR/../../ProjekAbsenta/backend/absenta_backend"
  sibling_backend="$DIR/../absenta_backend"
  if [ -d "$legacy_backend" ]; then
    BACKEND_PATH="$legacy_backend"
  else
    BACKEND_PATH="$sibling_backend"
  fi
fi
BACKEND_REPO="${BACKEND_REPO:-https://github.com/sharemovie1993/absenta_backend.git}"
BACKEND_BRANCH="${BACKEND_BRANCH:-master}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
NO_CACHE="${NO_CACHE:-false}"
RUN_MIGRATE="${RUN_MIGRATE:-true}"
STACK_DOWN_FIRST="${STACK_DOWN_FIRST:-true}"

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
    apt_ensure git
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

# Never prompt for git username/password in non-interactive deploy
export GIT_TERMINAL_PROMPT=0

if [ -z "$GITHUB_TOKEN" ]; then
  token_candidates=(
    "$DIR/../env/github.token"
    "$HOME/.config/absenta/github.token"
    "/etc/absenta/github.token"
  )
  for f in "${token_candidates[@]}"; do
    if [ -f "$f" ]; then
      GITHUB_TOKEN="$(tr -d '\r\n ' < "$f" || true)"
      break
    fi
  done
fi

# Use sudo for docker if current user lacks access to Docker daemon
DOCKER_BIN="docker"
if ! docker info >/dev/null 2>&1; then
  if is_cmd sudo && sudo -n true 2>/dev/null; then
    DOCKER_BIN="sudo docker"
  fi
fi

max_wait=180
waited=0
until $DOCKER_BIN info >/dev/null 2>&1; do
  waited=$((waited+5))
  if [ "$waited" -ge "$max_wait" ]; then
    echo "docker engine not ready"
    exit 1
  fi
  sleep 5
done

git_repo_url="$BACKEND_REPO"
if [ -n "$GITHUB_TOKEN" ]; then
  if [[ "$BACKEND_REPO" =~ ^https://github\.com/ ]]; then
    git_repo_url="https://x-access-token:${GITHUB_TOKEN}@github.com/${BACKEND_REPO#https://github.com/}"
  fi
fi

git_ssh_cmd=""
if [[ "$git_repo_url" =~ ^git@github\.com: ]] || [[ "$git_repo_url" =~ ^ssh://git@github\.com/ ]]; then
  git_ssh_cmd="ssh -o StrictHostKeyChecking=accept-new"
fi

if [ ! -d "$BACKEND_PATH" ]; then
  mkdir -p "$(dirname "$BACKEND_PATH")"
  if [ -n "$git_ssh_cmd" ]; then
    GIT_SSH_COMMAND="$git_ssh_cmd" git clone --branch "$BACKEND_BRANCH" --depth 1 "$git_repo_url" "$BACKEND_PATH" || {
      echo "Gagal clone repo backend (SSH). Pastikan deploy key sudah terpasang di VPS (non-interaktif)."
      exit 1
    }
  else
    git clone --branch "$BACKEND_BRANCH" --depth 1 "$git_repo_url" "$BACKEND_PATH" || {
      echo "Gagal clone repo backend (HTTPS)."
      echo ""
      echo "Cara paling mudah untuk repo PRIVATE:"
      echo "1) Buat GitHub Token (PAT) dengan akses repo (read)."
      echo "2) Simpan token di VPS (sekali saja):"
      echo "   sudo mkdir -p /etc/absenta"
      echo "   sudo sh -lc 'echo \"TOKEN_ANDA\" > /etc/absenta/github.token'"
      echo "   sudo chmod 600 /etc/absenta/github.token"
      echo "3) Jalankan lagi: bash deploy-multinode.sh"
      echo ""
      echo "Alternatif: export GITHUB_TOKEN=TOKEN_ANDA lalu jalankan script."
      exit 1
    }
  fi
else
  if [ -d "$BACKEND_PATH/.git" ]; then
    if [ -n "$git_ssh_cmd" ]; then
      GIT_SSH_COMMAND="$git_ssh_cmd" git -C "$BACKEND_PATH" fetch --prune origin "$BACKEND_BRANCH" || true
    else
      git -C "$BACKEND_PATH" fetch --prune origin "$BACKEND_BRANCH" || true
    fi
    git -C "$BACKEND_PATH" checkout "$BACKEND_BRANCH" || true
    if [ -n "$git_ssh_cmd" ]; then
      GIT_SSH_COMMAND="$git_ssh_cmd" git -C "$BACKEND_PATH" pull --ff-only origin "$BACKEND_BRANCH" || true
    else
      git -C "$BACKEND_PATH" pull --ff-only origin "$BACKEND_BRANCH" || true
    fi
  fi
fi

export BACKEND_PATH
$DOCKER_BIN compose -f "$COMPOSE_FILE" config >/dev/null

if [ "$STACK_DOWN_FIRST" = "true" ]; then
  $DOCKER_BIN compose -f "$COMPOSE_FILE" down || true
fi

build_args=()
if [ "$NO_CACHE" = "true" ]; then
  build_args+=(--no-cache)
fi
$DOCKER_BIN compose -f "$COMPOSE_FILE" build "${build_args[@]}"

env_dir="$DIR/../env"
tmp_env="/tmp/absenta-env.migrate.env"
umask 077
cat "$env_dir/env.common" "$env_dir/env.database" "$env_dir/env.redis" "$env_dir/env.production" > "$tmp_env" || true

if [ "$RUN_MIGRATE" = "true" ]; then
  $DOCKER_BIN run --rm \
    --env-file "$tmp_env" \
    -v "$BACKEND_PATH:/app" \
    -w /app \
    node:20-bookworm-slim \
    sh -lc "npm ci --no-audit --no-fund && npm run prisma:migrate:deploy"
fi

$DOCKER_BIN compose -f "$COMPOSE_FILE" up -d --remove-orphans
$DOCKER_BIN ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

ensure_standby() {
  local name="$1"
  local node_name="$2"
  local script="$3"
  if $DOCKER_BIN ps -a --format "{{.Names}}" | grep -q "^${name}\$" 2>/dev/null; then
    $DOCKER_BIN stop "$name" >/dev/null 2>&1 || true
    return 0
  fi
  local tmp="/tmp/absenta-worker-env-${node_name}.env"
  umask 077
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
if [ -n "$exited" ]; then
  for n in $exited; do
    echo "==== LOG: $n ===="
    $DOCKER_BIN logs "$n" || true
    echo "=================="
  done
fi
if command -v curl >/dev/null 2>&1; then
  curl -s -o /dev/null -w "health http %{http_code}\n" http://localhost:3001/health || true
fi
exit 0
