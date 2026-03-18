#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

need_cmd docker
need_cmd git

load_env_files

# Alamat repo (bisa di-override lewat env)
BACKEND_REPO="${BACKEND_REPO:-https://github.com/sharemovie1993/absenta_backend.git}"
FRONTEND_REPO="${FRONTEND_REPO:-https://github.com/sharemovie1993/absenta_frontend.git}"
BACKEND_BRANCH="${BACKEND_BRANCH:-master}"
FRONTEND_BRANCH="${FRONTEND_BRANCH:-master}"

# Jalur lokal
BACKEND_PATH="${BACKEND_PATH:-$DIR/../../../absenta_backend}"
FRONTEND_PATH="${FRONTEND_PATH:-$DIR/../../../absenta_frontend}"

# Fungsi helper untuk menambahkan token ke URL HTTPS jika ada
apply_git_token() {
  local url="$1"
  local user="${GITHUB_USERNAME:-}"
  local token="${GITHUB_TOKEN:-}"
  if [ -n "$token" ]; then
    # Jika URL diawali https://, sisipkan user:token@
    if [[ "$url" == https://* ]]; then
      local proto="https://"
      local rest="${url#https://}"
      if [ -n "$user" ]; then
        printf "https://%s:%s@%s" "$user" "$token" "$rest"
      else
        printf "https://%s@%s" "$token" "$rest"
      fi
      return
    fi
  fi
  printf "%s" "$url"
}

BACKEND_IMAGE="$(backend_image)"
FRONTEND_IMAGE="$(frontend_image)"

echo "=== Sync Source Code & Build Images ==="

# 1. Sync & Build Backend
REPO_URL_BE=$(apply_git_token "$BACKEND_REPO")
if [ ! -d "$BACKEND_PATH" ]; then
  echo "--> Folder Backend tidak ada. Melakukan clone..."
  git clone -b "$BACKEND_BRANCH" "$REPO_URL_BE" "$BACKEND_PATH" || { echo "Gagal clone backend"; exit 1; }
else
  echo "--> Folder Backend ditemukan. Melakukan update (git pull)..."
  (cd "$BACKEND_PATH" && git remote set-url origin "$REPO_URL_BE" && git pull origin "$BACKEND_BRANCH") || echo "Peringatan: Gagal pull backend, mencoba lanjut build..."
fi

if [ -d "$BACKEND_PATH" ]; then
  if [ -f "$BACKEND_PATH/Dockerfile" ]; then
    echo "--> Building Backend Image: $BACKEND_IMAGE..."
    docker build -t "$BACKEND_IMAGE" "$BACKEND_PATH"
    echo "OK: Backend built."
    echo "--> Importing Backend image to K3s (Mohon tunggu, ini memakan waktu)..."
    if is_cmd pv; then
      docker save "$BACKEND_IMAGE" | pv | as_root k3s ctr images import -
    else
      docker save "$BACKEND_IMAGE" | as_root k3s ctr images import -
    fi
    echo "OK: Backend imported to K3s."
  else
    echo "Kesalahan: Dockerfile tidak ditemukan di $BACKEND_PATH"
  fi
fi

# 2. Sync & Build Frontend
REPO_URL_FE=$(apply_git_token "$FRONTEND_REPO")
if [ ! -d "$FRONTEND_PATH" ]; then
  echo "--> Folder Frontend tidak ada. Melakukan clone..."
  git clone -b "$FRONTEND_BRANCH" "$REPO_URL_FE" "$FRONTEND_PATH" || { echo "Gagal clone frontend"; exit 1; }
else
  echo "--> Folder Frontend ditemukan. Melakukan update (git pull)..."
  (cd "$FRONTEND_PATH" && git remote set-url origin "$REPO_URL_FE" && git pull origin "$FRONTEND_BRANCH") || echo "Peringatan: Gagal pull frontend, mencoba lanjut build..."
fi

if [ -d "$FRONTEND_PATH" ]; then
  if [ -f "$FRONTEND_PATH/Dockerfile" ]; then
    echo "--> Building Frontend Image: $FRONTEND_IMAGE..."
    VITE_API_BASE_URL="${PUBLIC_APP_URL:-http://localhost:3001}/api"
    docker build \
      --build-arg VITE_API_BASE_URL="$VITE_API_BASE_URL" \
      -t "$FRONTEND_IMAGE" "$FRONTEND_PATH"
    echo "OK: Frontend built."
    echo "--> Importing Frontend image to K3s (Mohon tunggu, ini memakan waktu)..."
    # Pastikan image di-tag dengan nama yang lengkap agar K3s tidak bingung (docker.io/library/...)
    as_root k3s ctr images remove "docker.io/library/$FRONTEND_IMAGE" >/dev/null 2>&1 || true
    if is_cmd pv; then
      docker save "$FRONTEND_IMAGE" | pv | as_root k3s ctr images import -
    else
      docker save "$FRONTEND_IMAGE" | as_root k3s ctr images import -
    fi
    echo "OK: Frontend imported to K3s."
  else
    echo "Kesalahan: Dockerfile tidak ditemukan di $FRONTEND_PATH"
  fi
fi

echo "=== Build Complete ==="
echo "Images are ready. You can now deploy to K8s."
