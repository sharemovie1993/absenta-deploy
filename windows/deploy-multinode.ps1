Param(
  [string]$BackendPath = "C:\Users\SERVER-DELL\Documents\Projek Koprasi Sekolah\ProjekAbsenta\backend\absenta_backend",
  [string]$ComposeFile = "C:\Users\SERVER-DELL\Documents\Projek Koprasi Sekolah\absenta-deploy\windows\docker-compose.windows.yml",
  [string]$DatabaseUrl = "",
  [string]$AppVersion = "1.0.0"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Absenta Multi-Node (Windows Containers) Deployment ==="

# Pastikan Docker CLI tersedia
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Write-Host "Docker CLI belum terdeteksi. Memastikan Docker Desktop berjalan..."
}

# Pastikan Docker Desktop berjalan
try {
  $proc = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
  if (-not $proc) {
    Write-Host "-> Menjalankan Docker Desktop ..."
    Start-Process -FilePath 'C:\Program Files\Docker\Docker\Docker Desktop.exe' -ErrorAction SilentlyContinue | Out-Null
  } else {
    Write-Host "-> Docker Desktop sudah berjalan."
  }
} catch {
  Write-Warning "Gagal memulai Docker Desktop otomatis. Lanjutkan jika sudah berjalan secara manual."
}

# Tunggu engine siap dan pilih konteks Linux
Write-Host "-> Menunggu Docker engine siap (Linux) ..."
$maxWait = 180
$waited = 0
while ($waited -lt $maxWait) {
  try {
    docker context use desktop-linux | Out-Null
  } catch {}
  try {
    $info = docker info 2>$null
    if ($LASTEXITCODE -eq 0 -and $info) {
      Write-Host "   Docker engine siap."
      break
    }
  } catch {}
  Start-Sleep -Seconds 5
  $waited += 5
  Write-Host ("   menunggu... {0}s" -f $waited)
}
if ($waited -ge $maxWait) {
  Write-Warning "Docker engine belum siap. Silakan pastikan Docker Desktop berjalan dan Linux containers aktif (Settings > General > Use the WSL 2 based engine)."
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
  try {
    docker build -t absenta-backend:latest . | Write-Host
  } catch {
    Write-Warning "Build image gagal (engine belum siap?). Mencoba ulang singkat..."
    Start-Sleep -Seconds 8
    docker build -t absenta-backend:latest . | Write-Host
  }
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
try {
  Write-Host "-> Stop & remove containers (down)"
  docker compose -f "$ComposeFile" down | Write-Host

  Write-Host "-> Build images (no-cache)"
  docker compose -f "$ComposeFile" build --no-cache | Write-Host

  Write-Host "-> Start containers (up -d)"
  docker compose -f "$ComposeFile" up -d --remove-orphans | Write-Host
} catch {
  Write-Warning "Compose up gagal (engine/koneksi?). Mencoba ulang singkat..."
  Start-Sleep -Seconds 8
  docker compose -f "$ComposeFile" up -d --remove-orphans | Write-Host
}

Write-Host "-> Menampilkan status containers"
try {
  docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | Write-Host
} catch {
  Write-Warning "Gagal mengambil daftar container (engine belum siap?)."
}

# Dump logs for exited containers (diagnostic)
try {
  $exited = docker ps -a --filter "status=exited" --format "{{.Names}}"
  if ($exited) {
    Write-Warning "Terdapat container Exited. Menampilkan log:"
    $names = $exited -split "`n"
    foreach ($n in $names) {
      if ($n) {
        Write-Host "==== LOG: $n ===="
        docker logs $n | Write-Host
        Write-Host "=================="
      }
    }
  }
} catch {
  Write-Warning "Gagal mengambil log container yang Exited."
}

Write-Host "-> Cek health backend API (http://localhost:3001/health)"
try {
  $resp = Invoke-WebRequest -Uri "http://localhost:3001/health" -UseBasicParsing -TimeoutSec 10
  Write-Host ("Health code: " + $resp.StatusCode)
} catch {
  Write-Warning "Health check gagal (API mungkin masih starting)."
}

Write-Host "Selesai."
exit 0
