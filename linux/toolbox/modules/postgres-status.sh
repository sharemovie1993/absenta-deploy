#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

echo "=== PostgreSQL Status ==="
if is_cmd systemctl; then
  as_root systemctl status postgresql --no-pager || true
  echo ""
fi

if is_cmd psql; then
  as_root psql --version || true
else
  echo "psql not found"
fi

