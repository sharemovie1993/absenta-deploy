#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

need_cmd systemctl

apt_ensure chrony
as_root systemctl enable --now chrony >/dev/null 2>&1 || true

echo "Chrony enabled"
as_root systemctl status chrony --no-pager || true
echo ""
if is_cmd chronyc; then
  chronyc sources -v || true
fi

