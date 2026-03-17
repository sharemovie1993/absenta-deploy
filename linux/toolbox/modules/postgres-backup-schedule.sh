#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

ensure_systemd
need_cmd cron

read -rp "DB name (contoh absenta): " DB_NAME
read -rp "Backup dir [/var/backups/postgresql]: " OUT_DIR
OUT_DIR="${OUT_DIR:-/var/backups/postgresql}"
read -rp "Retensi hari (hapus backup lebih lama) [14]: " RET_DAYS
RET_DAYS="${RET_DAYS:-14}"
read -rp "Jadwal (cron) [15 2 * * *] : " CRON_EXPR
CRON_EXPR="${CRON_EXPR:-15 2 * * *}"

[ -n "${DB_NAME:-}" ] || { echo "DB_NAME kosong"; exit 1; }

bin="/usr/local/bin/absenta_pg_backup.sh"
as_root bash -lc "cat > '$bin' <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

DB_NAME=\"\${1:-}\"
OUT_DIR=\"\${2:-/var/backups/postgresql}\"
RET_DAYS=\"\${3:-14}\"

[ -n \"\$DB_NAME\" ] || { echo \"DB_NAME required\"; exit 1; }
mkdir -p \"\$OUT_DIR\"
chmod 700 \"\$OUT_DIR\" || true

ts=\"\$(date +%Y%m%d_%H%M%S)\"
out=\"\${OUT_DIR}/\${DB_NAME}_\${ts}.sql.gz\"

sudo -u postgres pg_dump \"\$DB_NAME\" | gzip -9 > \"\$out\"
chmod 600 \"\$out\" || true

find \"\$OUT_DIR\" -type f -name \"\${DB_NAME}_*.sql.gz\" -mtime \"+\${RET_DAYS}\" -delete || true
EOF"
as_root chmod +x "$bin"

cronfile="/etc/cron.d/absenta-postgres-backup"
as_root bash -lc "cat > '$cronfile' <<EOF
${CRON_EXPR} root ${bin} ${DB_NAME} ${OUT_DIR} ${RET_DAYS}
EOF"
as_root chmod 644 "$cronfile"

echo "OK scheduled."
echo "- script: $bin"
echo "- cron:   $cronfile"

