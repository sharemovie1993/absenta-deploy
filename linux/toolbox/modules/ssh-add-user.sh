#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

need_cmd useradd
need_cmd id

read -rp "Username baru: " USERNAME
USERNAME="$(canonicalize_node_id "$USERNAME")"
[ -n "${USERNAME:-}" ] || { echo "Username kosong"; exit 1; }

if id "$USERNAME" >/dev/null 2>&1; then
  echo "User sudah ada: $USERNAME"
else
  as_root useradd -m -s /bin/bash "$USERNAME"
  echo "User dibuat: $USERNAME"
fi

read -rp "Tambahkan ke sudo? (y/n) [y]: " ans
ans="${ans:-y}"
if [ "${ans,,}" = "y" ]; then
  if getent group sudo >/dev/null 2>&1; then
    as_root usermod -aG sudo "$USERNAME"
  elif getent group wheel >/dev/null 2>&1; then
    as_root usermod -aG wheel "$USERNAME"
  fi
  echo "OK sudo group updated"
fi

echo "Saran: lanjutkan Add SSH public key untuk user ini"

