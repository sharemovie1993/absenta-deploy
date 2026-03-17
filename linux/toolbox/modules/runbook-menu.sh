#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"

viewer() {
  local f="$1"
  if command -v less >/dev/null 2>&1; then
    less -R "$f"
    return
  fi
  cat "$f"
  echo ""
  read -rp "Enter untuk kembali..." _
}

list_files() {
  echo "=== Runbook Menu ==="
  echo "Lokasi: $ROOT"
  echo ""

  files=()
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$ROOT" -maxdepth 1 -type f -name "*.md" -print0 2>/dev/null || true)

  if [ "${#files[@]}" -eq 0 ]; then
    echo "Tidak ada file .md di $ROOT"
    return 1
  fi

  i=1
  for f in "${files[@]}"; do
    echo "${i}) $(basename "$f")"
    i=$((i+1))
  done
  echo "0) Back"

  read -rp "Pilih dokumen: " opt
  if [ "${opt:-}" = "0" ]; then
    exit 0
  fi
  if ! [[ "${opt:-}" =~ ^[0-9]+$ ]]; then
    echo "Input tidak valid"
    return 0
  fi
  idx=$((opt-1))
  if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#files[@]}" ]; then
    echo "Pilihan di luar range"
    return 0
  fi
  viewer "${files[$idx]}"
}

while true; do
  list_files || true
done

