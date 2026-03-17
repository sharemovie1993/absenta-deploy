#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

need_cmd apt-get
need_cmd dpkg
need_cmd systemctl

ensure_postgres
as_root systemctl enable --now postgresql >/dev/null 2>&1 || true

echo "PostgreSQL installed"
as_root psql --version || true

