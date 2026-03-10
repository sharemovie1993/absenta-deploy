# Absenta Deployment Environment

## Tujuan
- Memecah konfigurasi environment menjadi layer modular sesuai praktik DevOps.
- Menghindari `.env` tunggal yang besar dan rawan konflik.
- Mempermudah override per environment (local, staging, production) dan per node.

## Struktur Berkas
```
absenta-deploy/
├─ env/
│  ├─ env.common
│  ├─ env.database
│  ├─ env.redis
│  ├─ env.payment
│  ├─ env.email
│  └─ env.production
└─ windows/
   └─ docker-compose.windows.yml
```

### env.common (core runtime)
- NODE_ENV, HOST, PORT
- NODE_ID, APP_VERSION, WORKER_VERSION
- JWT_SECRET
- PUBLIC_APP_URL, PUBLIC_INVOICE_BASE_URL

### env.database
- DATABASE_URL

### env.redis
- REDIS_URL, CACHE_TTL_DEFAULT

### env.payment
- TRIPAY_API_KEY, TRIPAY_PRIVATE_KEY, TRIPAY_MERCHANT_CODE, TRIPAY_WEBHOOK_URL
- MIDTRANS_SERVER_KEY, MIDTRANS_CLIENT_KEY
- STRIPE_SECRET_KEY, STRIPE_PUBLISHABLE_KEY

### env.email
- EMAIL_HOST, EMAIL_PORT, EMAIL_SECURE, EMAIL_USER, EMAIL_PASS
- EMAIL_FROM, ALERT_EMAIL

### env.production
- ENABLE_DEBUG_LOGS, MAINTENANCE_MODE, BILLING_CRON_ENABLED

## Penggunaan di Compose
### Backend API
Memuat semua layer:
```
env_file:
  - ../env/env.common
  - ../env/env.database
  - ../env/env.redis
  - ../env/env.payment
  - ../env/env.email
  - ../env/env.production
```

### Worker Containers
Memuat subset:
```
env_file:
  - ../env/env.common
  - ../env/env.database
  - ../env/env.redis
  - ../env/env.production
```

## Keamanan Kredensial
- Jangan hardcode kredensial di Dockerfile/source code.
- Simpan nilai sensitif di berkas `env/*` (ter-ignore oleh Git).
- Hanya berkas contoh yang boleh dipublish (`*.example`).

## Override di Production
- Buat salinan setiap berkas env sesuai kebutuhan host.
- Gunakan `docker compose -f <compose> --env-file <file> up -d` bila perlu substitusi variabel.
- Untuk Kubernetes/Swarm, map setiap key ke Secret/Config.

## Validasi
Jalankan dari folder compose:
```
docker compose -f docker-compose.windows.yml config
```
Pastikan setiap service menampilkan daftar `env_file` yang sesuai tanpa error.

## Catatan Multi-node
- Identitas node ditentukan oleh `NODE_NAME` di service, sedangkan `NODE_ID` (env.common) bisa digunakan untuk metadata/telemetri.
- Semua worker dan API berbagi Redis yang sama (adapter queue).
