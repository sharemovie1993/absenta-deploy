#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

ensure_systemd
need_cmd tar
need_cmd uname

version="${NODE_EXPORTER_VERSION:-1.8.1}"
arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) arch="amd64" ;;
  aarch64|arm64) arch="arm64" ;;
  *) echo "Unsupported arch: $arch"; exit 1 ;;
esac

tmp="$(mktemp -d)"
tgz="$tmp/node_exporter.tar.gz"
url="https://github.com/prometheus/node_exporter/releases/download/v${version}/node_exporter-${version}.linux-${arch}.tar.gz"

echo "Downloading node_exporter v${version} (${arch})"
download_file "$url" "$tgz"

tar -xzf "$tgz" -C "$tmp"
bin="$tmp/node_exporter-${version}.linux-${arch}/node_exporter"

if ! id node_exporter >/dev/null 2>&1; then
  as_root useradd -r -s /usr/sbin/nologin node_exporter || true
fi

as_root install -m 0755 "$bin" /usr/local/bin/node_exporter

svc="/etc/systemd/system/node_exporter.service"
as_root bash -lc "cat > '$svc' <<EOF
[Unit]
Description=Prometheus Node Exporter
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF"

as_root systemctl daemon-reload
as_root systemctl enable --now node_exporter

echo "Node Exporter installed and running"
echo "Metrics: http://<server-ip>:9100/metrics"

