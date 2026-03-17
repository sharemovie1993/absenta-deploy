#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

cfg="/etc/ssh/sshd_config"

echo "=== SSH Status ==="
echo "sshd_config: $cfg"
if [ -f "$cfg" ]; then
  echo ""
  echo "Effective-like settings (best effort):"
  grep -E '^(Port|PasswordAuthentication|PermitRootLogin|PubkeyAuthentication|ChallengeResponseAuthentication|KbdInteractiveAuthentication)\s' "$cfg" || true
fi
echo ""
if is_cmd ss; then
  echo "Listening SSH ports:"
  ss -ltnp | grep -E 'sshd' || true
fi
echo ""
if is_cmd systemctl; then
  as_root systemctl status ssh --no-pager || as_root systemctl status sshd --no-pager || true
fi

