# Absenta Toolbox (Infra Ops)

Toolbox ini adalah “dapur/bengkel” untuk operasi infrastruktur, supaya owner bisa melakukan instalasi dan konfigurasi dependency lewat menu script (tanpa edit manual).

## Jalankan

```bash
cd absenta-deploy/linux/toolbox
chmod +x absenta-toolbox.sh modules/*.sh lib/*.sh
./absenta-toolbox.sh
```

## Isi Menu

- Status server (CPU/RAM/Disk/Port/WireGuard/Docker)
- Firewall (UFW): enable safe defaults, allow SSH/HTTP/HTTPS/WireGuard, add/remove rules
- Hardening basic: unattended-upgrades + fail2ban + ufw safe defaults
- WireGuard: install, init server, add client, status
- PostgreSQL: install, konfigurasi listen + pg_hba untuk subnet WireGuard, buat database+user
- PostgreSQL backup scheduler: cron harian + rotasi retensi
- Redis: install, konfigurasi bind + requirepass untuk WireGuard, status
- SSH: add user, add key, hardening (disable password, disable root login, optional port), status
- Network (Ubuntu netplan): tampilkan config, generate & apply via `netplan try` (auto-rollback)
- Time sync: chrony

## Prinsip Keamanan

- Semua konfigurasi yang mengubah file sistem membuat backup `.bak_<timestamp>`.
- Firewall “enable safe defaults” selalu memastikan SSH di-allow dulu.
- PostgreSQL dan Redis disarankan hanya bind ke IP WireGuard, bukan IP publik.
- Password diminta via input tersembunyi.
- Netplan memakai `netplan try` agar rollback otomatis jika koneksi putus.
- Node exporter untuk metrics CPU/RAM/disk (port 9100)

## Catatan

Toolbox ini bersifat konservatif dan fokus pada skenario single VPS + WireGuard. Untuk cluster besar, beberapa langkah biasanya dipindahkan ke managed services.
