#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
  echo "Uninstalling k3s"
  as_root /usr/local/bin/k3s-uninstall.sh
  echo "k3s removed"
  exit 0
fi

echo "k3s-uninstall.sh not found"
exit 1

