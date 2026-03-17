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

# Jalur lokal (bisa di-override lewat env)
BACKEND_PATH="${BACKEND_PATH:-$DIR/../../../absenta_backend}"
FRONTEND_PATH="${FRONTEND_PATH:-$DIR/../../../absenta_frontend}"

BACKEND_IMAGE="$(backend_image)"
FRONTEND_IMAGE="$(frontend_image)"

echo "=== Sync Source Code & Build Images ==="

# 1. Sync & Build Backend
if [ ! -d "$BACKEND_PATH" ]; then
  echo "--> Folder Backend tidak ada. Melakukan clone dari $BACKEND_REPO..."
  git clone -b "$BACKEND_BRANCH" "$BACKEND_REPO" "$BACKEND_PATH"
else
  echo "--> Folder Backend ditemukan. Melakukan update (git pull)..."
  cd "$BACKEND_PATH" && git pull origin "$BACKEND_BRANCH" && cd -
fi

if [ -d "$BACKEND_PATH" ]; then
  echo "--> Building Backend Image: $BACKEND_IMAGE..."
  docker build -t "$BACKEND_IMAGE" "$BACKEND_PATH"
  echo "OK: Backend built."
fi

# 2. Sync & Build Frontend
if [ ! -d "$FRONTEND_PATH" ]; then
  echo "--> Folder Frontend tidak ada. Melakukan clone dari $FRONTEND_REPO..."
  git clone -b "$FRONTEND_BRANCH" "$FRONTEND_REPO" "$FRONTEND_PATH"
else
  echo "--> Folder Frontend ditemukan. Melakukan update (git pull)..."
  cd "$FRONTEND_PATH" && git pull origin "$FRONTEND_BRANCH" && cd -
fi

if [ -d "$FRONTEND_PATH" ]; then
  echo "--> Building Frontend Image: $FRONTEND_IMAGE..."
  VITE_API_BASE_URL="${PUBLIC_APP_URL:-http://localhost:3001}/api"
  docker build \
    --build-arg VITE_API_BASE_URL="$VITE_API_BASE_URL" \
    -t "$FRONTEND_IMAGE" "$FRONTEND_PATH"
  echo "OK: Frontend built."
fi

echo "=== Build Complete ==="
echo "Images are ready. You can now deploy to K8s."
