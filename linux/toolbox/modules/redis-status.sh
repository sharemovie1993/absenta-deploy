#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

echo "=== Redis Status ==="
if is_cmd systemctl; then
  as_root systemctl status redis-server --no-pager || true
  echo ""
fi

if is_cmd redis-cli; then
  redis-cli ping || true
else
  echo "redis-cli not found"
fi

