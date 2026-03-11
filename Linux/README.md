# Deploy Absenta (Linux / VPS)

## Prasyarat
- Ubuntu 22.04+ (direkomendasikan)
- Akses sudo
- Port terbuka: 3001 (API) dan 6379 (Redis) jika memakai Redis internal compose
- Database PostgreSQL sudah tersedia dan kredensialnya siap

## Struktur
- `linux/docker-compose.linux.yml` (Redis internal + API + workers)
- `linux/docker-compose.linux.external-redis.yml` (tanpa Redis service)
- `linux/deploy-multinode.sh` (script deploy idempotent)

## Konfigurasi ENV
Edit berkas di `../env/`:
- `env.common`
- `env.database` (wajib: `DATABASE_URL=...`)
- `env.redis` (wajib: `REDIS_URL=...`)
- `env.production`
- Opsional: `env.payment`, `env.email` (dipakai oleh backend-api)

## Deploy (Redis internal)
Jalankan dari server VPS:

```bash
cd absenta-deploy/linux
chmod +x deploy-multinode.sh
./deploy-multinode.sh
```

## Deploy (Redis eksternal)

```bash
cd absenta-deploy/linux
COMPOSE_FILE="$PWD/docker-compose.linux.external-redis.yml" ./deploy-multinode.sh
```

## Override lokasi source backend
Default script akan:
- pakai path legacy jika ada: `../../ProjekAbsenta/backend/absenta_backend`
- jika tidak ada: clone ke `../absenta_backend`

Untuk menentukan lokasi sendiri:

```bash
BACKEND_PATH=/opt/absenta/absenta_backend ./deploy-multinode.sh
```

## Migrate DB (Prisma)
Default `deploy-multinode.sh` menjalankan migrate otomatis via container Node:
- `npm run prisma:migrate:deploy`

Untuk mematikan migrate:

```bash
RUN_MIGRATE=false ./deploy-multinode.sh
```

## Health check
Script akan cek:
- `http://localhost:3001/health`

Jika memakai reverse proxy, pastikan upstream mengarah ke port `3001`.

## Load test (real attendance)
Disarankan menjalankan k6 dari mesin terpisah (bukan VPS yang sama) untuk menghindari limit socket/ephemeral port.

Output summary k6 diarahkan ke:
- `ProjekAbsenta/backend/absenta_backend/logs/loadtest/*.json`

