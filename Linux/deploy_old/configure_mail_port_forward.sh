#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

echo "=== Wizard Konfigurasi Port Forward Mail Server (SMTP/IMAP) ==="
echo ""
echo "Script ini akan:"
echo "- Mengecek ketersediaan iptables dan ip command"
echo "- Menampilkan ringkasan aturan NAT terkait port mail saat ini"
echo "- Menambahkan DNAT dari IP publik VPS ke IP mail server di tunnel"
echo "- Menambahkan aturan FORWARD dan MASQUERADE jika diperlukan"
echo ""

# Auto-install dependencies
echo "Memeriksa dependensi..."
DEPS_TO_INSTALL=""

if ! command -v iptables >/dev/null 2>&1; then
  echo "  - iptables tidak ditemukan."
  DEPS_TO_INSTALL="$DEPS_TO_INSTALL iptables"
fi

if ! command -v ip >/dev/null 2>&1; then
  echo "  - iproute2 (ip command) tidak ditemukan."
  DEPS_TO_INSTALL="$DEPS_TO_INSTALL iproute2"
fi

if ! command -v netfilter-persistent >/dev/null 2>&1; then
  echo "  - netfilter-persistent tidak ditemukan."
  DEPS_TO_INSTALL="$DEPS_TO_INSTALL iptables-persistent netfilter-persistent"
fi

if [ -n "$DEPS_TO_INSTALL" ]; then
  echo "Menginstall paket yang diperlukan: $DEPS_TO_INSTALL ..."
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y $DEPS_TO_INSTALL
  echo "Dependensi berhasil diinstall."
else
  echo "Semua dependensi sudah terpasang."
fi

echo ""

if ! command -v iptables >/dev/null 2>&1; then
  echo "Gagal menginstall iptables."
  exit 1
fi

DEFAULT_MAIL_IP="10.50.0.4"
read -p "IP internal mail server (default ${DEFAULT_MAIL_IP}): " MAIL_IP
MAIL_IP=${MAIL_IP:-$DEFAULT_MAIL_IP}

if [ -z "$MAIL_IP" ]; then
  echo "IP mail server tidak boleh kosong."
  exit 1
fi

DEFAULT_WG_IF="wg0"
read -p "Nama interface WireGuard untuk tunnel (default ${DEFAULT_WG_IF}): " WG_IFACE
WG_IFACE=${WG_IFACE:-$DEFAULT_WG_IF}

PUBLIC_IF=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')
if [ -z "$PUBLIC_IF" ]; then
  PUBLIC_IF=$(ip route show default 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')
fi

echo "Interface publik terdeteksi: ${PUBLIC_IF:-tidak terdeteksi}"
read -p "Nama interface publik keluar internet (default ${PUBLIC_IF:-eth0}): " IFACE_OUT
IFACE_OUT=${IFACE_OUT:-${PUBLIC_IF:-eth0}}

echo ""
echo "=== Ringkasan aturan NAT terkait port mail SEBELUM perubahan ==="
iptables -t nat -S PREROUTING 2>/dev/null | grep -E 'dport (25|465|587|993|995)' || echo "(Tidak ada aturan PREROUTING khusus port mail yang terdeteksi)"
echo ""
echo "Aturan FORWARD terkait IP ${MAIL_IP}:"
iptables -S FORWARD 2>/dev/null | grep -F "$MAIL_IP" || echo "(Tidak ada aturan FORWARD spesifik untuk ${MAIL_IP} yang terdeteksi)"
echo ""

MAIL_PORTS="25 465 587 110 995 143 993"

# Fungsi helper untuk membersihkan aturan lama yang konflik (target berbeda)
ensure_dnat_rule() {
  local IFACE=$1
  local PORT=$2
  local TARGET=$3 # IP:PORT

  # 1. Cleanup: Hapus aturan DNAT pada port/interface yang sama TAPI target berbeda
  # Ambil semua aturan PREROUTING yang match interface & port
  iptables -t nat -S PREROUTING | grep "\-i $IFACE" | grep "\-p tcp" | grep "\-\-dport $PORT" | grep "\-j DNAT" | while read -r rule; do
    # Cek apakah rule ini mengarah ke target yang diinginkan
    if echo "$rule" | grep -q "\-\-to-destination $TARGET"; then
       # Match, biarkan (nanti dicek lagi di langkah 2)
       continue
    else
       # Tidak match (conflict/old), hapus
       local del_cmd="${rule/-A/-D}"
       echo "  - [CLEANUP] Menghapus aturan lama/konflik: $del_cmd"
       iptables -t nat $del_cmd
    fi
  done

  # 2. Idempotency: Cek apakah aturan yang diinginkan sudah ada
  if iptables -t nat -C PREROUTING -i "$IFACE" -p tcp --dport "$PORT" -j DNAT --to-destination "$TARGET" 2>/dev/null; then
    echo "  - [OK] Aturan DNAT sudah sesuai."
  else
    iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport "$PORT" -j DNAT --to-destination "$TARGET"
    echo "  - [ADD] Aturan DNAT ditambahkan."
  fi
}

ensure_forward_in_rule() {
  local IFACE_IN=$1
  local IFACE_OUT=$2
  local DEST_IP=$3
  local PORT=$4

  # Cleanup: Hapus aturan FORWARD (IN->WG) pada port yang sama tapi IP tujuan beda (jika ada)
  # Ini agak agresif, jadi kita batasi hanya hapus jika benar-benar konflik di port yang sama
  iptables -S FORWARD | grep "\-i $IFACE_IN" | grep "\-o $IFACE_OUT" | grep "\-p tcp" | grep "\-\-dport $PORT" | while read -r rule; do
     if echo "$rule" | grep -q "\-d $DEST_IP"; then
        continue
     else
        local del_cmd="${rule/-A/-D}"
        echo "  - [CLEANUP] Menghapus aturan FORWARD lama: $del_cmd"
        iptables $del_cmd
     fi
  done

  if iptables -C FORWARD -i "$IFACE_IN" -o "$IFACE_OUT" -p tcp -d "$DEST_IP" --dport "$PORT" -j ACCEPT 2>/dev/null; then
    echo "  - [OK] Aturan FORWARD (IN -> WG) sudah ada."
  else
    iptables -A FORWARD -i "$IFACE_IN" -o "$IFACE_OUT" -p tcp -d "$DEST_IP" --dport "$PORT" -j ACCEPT
    echo "  - [ADD] Aturan FORWARD (IN -> WG) ditambahkan."
  fi
}

ensure_forward_out_rule() {
  local IFACE_IN=$1
  local IFACE_OUT=$2
  local SOURCE_IP=$3
  local PORT=$4

  # Cleanup: Hapus aturan FORWARD (WG->OUT) pada port yang sama tapi IP sumber beda
  iptables -S FORWARD | grep "\-i $IFACE_IN" | grep "\-o $IFACE_OUT" | grep "\-p tcp" | grep "\-\-sport $PORT" | while read -r rule; do
     if echo "$rule" | grep -q "\-s $SOURCE_IP"; then
        continue
     else
        local del_cmd="${rule/-A/-D}"
        echo "  - [CLEANUP] Menghapus aturan FORWARD lama: $del_cmd"
        iptables $del_cmd
     fi
  done

  if iptables -C FORWARD -i "$IFACE_IN" -o "$IFACE_OUT" -p tcp -s "$SOURCE_IP" --sport "$PORT" -j ACCEPT 2>/dev/null; then
    echo "  - [OK] Aturan FORWARD (WG -> OUT) sudah ada."
  else
    iptables -A FORWARD -i "$IFACE_IN" -o "$IFACE_OUT" -p tcp -s "$SOURCE_IP" --sport "$PORT" -j ACCEPT
    echo "  - [ADD] Aturan FORWARD (WG -> OUT) ditambahkan."
  fi
}

for PORT in $MAIL_PORTS; do
  echo "Memproses Port TCP ${PORT}..."
  
  ensure_dnat_rule "$IFACE_OUT" "$PORT" "${MAIL_IP}:${PORT}"
  ensure_forward_in_rule "$IFACE_OUT" "$WG_IFACE" "$MAIL_IP" "$PORT"
  ensure_forward_out_rule "$WG_IFACE" "$IFACE_OUT" "$MAIL_IP" "$PORT"
  
done

echo ""
echo "Memastikan aturan MASQUERADE untuk trafik keluar dari ${MAIL_IP} melalui ${IFACE_OUT} ..."
if iptables -t nat -C POSTROUTING -s "$MAIL_IP" -o "$IFACE_OUT" -j MASQUERADE 2>/dev/null; then
  echo "  - [OK] Aturan MASQUERADE sudah ada."
else
  iptables -t nat -A POSTROUTING -s "$MAIL_IP" -o "$IFACE_OUT" -j MASQUERADE
  echo "  - [ADD] Aturan MASQUERADE ditambahkan."
fi

echo ""
echo "=== Ringkasan aturan NAT terkait port mail SETELAH perubahan ==="
iptables -t nat -S PREROUTING 2>/dev/null | grep -E 'dport (25|465|587|110|995|143|993)' || echo "(Tidak ada aturan PREROUTING khusus port mail yang terdeteksi)"
echo ""
echo "Aturan FORWARD terkait IP ${MAIL_IP}:"
iptables -S FORWARD 2>/dev/null | grep -F "$MAIL_IP" || echo "(Tidak ada aturan FORWARD spesifik untuk ${MAIL_IP} yang terdeteksi)"
echo ""

if command -v netfilter-persistent >/dev/null 2>&1; then
  echo "Menyimpan konfigurasi iptables via netfilter-persistent..."
  netfilter-persistent save || echo "Gagal menyimpan iptables via netfilter-persistent."
else
  echo "WARNING: netfilter-persistent gagal dijalankan meskipun sudah diinstall."
fi

echo ""
echo "Wizard konfigurasi port forward mail server selesai."

