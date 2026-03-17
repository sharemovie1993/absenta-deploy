#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

need_cmd apt-get
need_cmd dpkg
need_cmd systemctl

ensure_redis
as_root systemctl enable --now redis-server >/dev/null 2>&1 || true

echo "Redis installed"
if is_cmd redis-server; then redis-server --version || true; fi

