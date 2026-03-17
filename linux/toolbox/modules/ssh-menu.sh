#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

run_status() { bash "$DIR/ssh-status.sh"; }
run_add_user() { bash "$DIR/ssh-add-user.sh"; }
run_add_key() { bash "$DIR/ssh-add-key.sh"; }
run_harden() { bash "$DIR/ssh-harden.sh"; }

while true; do
  echo ""
  echo "=== SSH Menu ==="
  echo "1) Status SSH (port/auth/root)"
  echo "2) Add user (opsional sudo)"
  echo "3) Add SSH public key ke user"
  echo "4) Hardening SSH (disable password, disable root login, optional port)"
  echo "0) Back"
  read -rp "Pilih: " opt
  case "${opt:-}" in
    1) run_status ;;
    2) run_add_user ;;
    3) run_add_key ;;
    4) run_harden ;;
    0) exit 0 ;;
    *) echo "Pilihan tidak dikenal" ;;
  esac
done

