Param(
  [string]$BackendPath = "C:\Users\SERVER-DELL\Documents\Projek Koprasi Sekolah\ProjekAbsenta\backend\absenta_backend",
  [string]$ComposeFile = "C:\Users\SERVER-DELL\Documents\Projek Koprasi Sekolah\absenta-deploy\windows\docker-compose.windows.yml",
  [string]$DatabaseUrl = "",
  [string]$AppVersion = "1.0.0"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Absenta Multi-Node (Windows Containers) Deployment ==="

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Write-Error "Docker tidak ditemukan di PATH. Mohon install Docker Desktop for Windows."
  exit 1
}

if (-not (Test-Path $BackendPath)) {
  Write-Error "Path backend tidak ditemukan: $BackendPath"
  exit 1
}

Push-Location $BackendPath
try {
  Write-Host "-> Build backend artifacts (npm run build)"
  npm run build | Write-Host

  Write-Host "-> Build Docker image: absenta-backend:latest"
  docker build -t absenta-backend:latest . | Write-Host
} finally {
  Pop-Location
}

if (-not (Test-Path $ComposeFile)) {
  Write-Error "File compose tidak ditemukan: $ComposeFile"
  exit 1
}

if ($DatabaseUrl -ne "") {
  $env:DATABASE_URL = $DatabaseUrl
}
$env:APP_VERSION = $AppVersion

Write-Host "-> Menjalankan stack: docker compose -f $ComposeFile up -d --remove-orphans"
docker compose -f "$ComposeFile" up -d --remove-orphans | Write-Host

Write-Host "-> Menampilkan status containers"
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | Write-Host

Write-Host "-> Cek health backend API (http://localhost:3000/health)"
try {
  $resp = Invoke-WebRequest -Uri "http://localhost:3000/health" -UseBasicParsing -TimeoutSec 10
  Write-Host ("Health code: " + $resp.StatusCode)
} catch {
  Write-Warning "Health check gagal (API mungkin masih starting)."
}

Write-Host "Selesai."
exit 0
