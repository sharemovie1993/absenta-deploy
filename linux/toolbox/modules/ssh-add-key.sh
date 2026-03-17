#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

need_cmd id

read -rp "Username target: " USERNAME
USERNAME="$(canonicalize_node_id "$USERNAME")"
[ -n "${USERNAME:-}" ] || { echo "Username kosong"; exit 1; }
id "$USERNAME" >/dev/null 2>&1 || { echo "User tidak ditemukan: $USERNAME"; exit 1; }

read -rp "SSH public key (tempel satu baris key): " PUBKEY
[ -n "${PUBKEY:-}" ] || { echo "Public key kosong"; exit 1; }

home_dir="$(getent passwd "$USERNAME" | awk -F: '{print $6}')"
[ -n "${home_dir:-}" ] || { echo "Home dir tidak ditemukan"; exit 1; }

ssh_dir="${home_dir}/.ssh"
auth="${ssh_dir}/authorized_keys"

as_root mkdir -p "$ssh_dir"
as_root chmod 700 "$ssh_dir"
as_root touch "$auth"
as_root chmod 600 "$auth"
as_root chown -R "${USERNAME}:${USERNAME}" "$ssh_dir"

if as_root grep -qF "$PUBKEY" "$auth"; then
  echo "Key sudah ada di authorized_keys"
  exit 0
fi

as_root bash -lc "printf '%s\n' \"$PUBKEY\" >> '$auth'"
as_root chown "${USERNAME}:${USERNAME}" "$auth"
echo "OK key ditambahkan"

