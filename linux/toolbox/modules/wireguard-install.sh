#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

need_cmd apt-get
need_cmd dpkg

ensure_wireguard_tools
echo "WireGuard installed"

