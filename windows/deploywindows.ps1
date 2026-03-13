Param(
  [string]$BackendPath = "C:\Users\SERVER-DELL\Documents\Projek Koprasi Sekolah\ProjekAbsenta\backend\absenta_backend",
  [string]$ComposeFile = "",
  [ValidateSet("", "single", "multi")]
  [string]$Mode = "",
  [ValidateSet("", "deploy", "status", "logs_api", "restart", "stop", "cleanup")]
  [string]$Action = "",
  [switch]$NonInteractive,
  [string]$DatabaseUrl = "",
  [string]$AppVersion = "1.0.0"
)

$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot

function Prompt-Text {
  param(
    [string]$Label,
    [string]$DefaultValue = ""
  )
  $v = Read-Host ($Label + ($(if ($DefaultValue -ne "") { " [$DefaultValue]" } else { "" })))
  if ([string]::IsNullOrWhiteSpace($v)) { return $DefaultValue }
  return $v.Trim()
}

function Prompt-YesNo {
  param(
    [string]$Label,
    [bool]$DefaultYes = $true
  )
  $suffix = $(if ($DefaultYes) { "[Y/n]" } else { "[y/N]" })
  $v = Read-Host ($Label + " " + $suffix)
  if ([string]::IsNullOrWhiteSpace($v)) { return $DefaultYes }
  $t = $v.Trim().ToLowerInvariant()
  if ($t -in @("y", "yes", "ya")) { return $true }
  if ($t -in @("n", "no", "tidak", "t")) { return $false }
  return $DefaultYes
}

function Read-EnvFile {
  param(
    [string]$Path
  )
  $map = @{}
  if (-not (Test-Path $Path)) { return $map }
  $lines = Get-Content -Path $Path -ErrorAction SilentlyContinue
  foreach ($ln in $lines) {
    $line = ("$ln").Trim()
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line.StartsWith("#")) { continue }
    $idx = $line.IndexOf("=")
    if ($idx -lt 1) { continue }
    $k = $line.Substring(0, $idx).Trim()
    $v = $line.Substring($idx + 1)
    if ($k -ne "") { $map[$k] = $v }
  }
  return $map
}

function Get-HostFromUrl {
  param(
    [string]$Value
  )
  if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
  $v = $Value.Trim()
  $uri = $null
  if ([Uri]::TryCreate($v, [UriKind]::Absolute, [ref]$uri) -and $uri.Host) { return $uri.Host }
  if (-not ($v -match "^[a-zA-Z][a-zA-Z0-9+\-.]*://")) {
    if ([Uri]::TryCreate(("https://" + $v), [UriKind]::Absolute, [ref]$uri) -and $uri.Host) { return $uri.Host }
  }
  return ""
}

function Set-EnvIfEmpty {
  param(
    [string]$Name,
    [string]$Value
  )
  if ([string]::IsNullOrWhiteSpace($Value)) { return }
  $cur = ""
  try { $cur = (Get-Item -Path ("env:" + $Name) -ErrorAction SilentlyContinue).Value } catch {}
  if ([string]::IsNullOrWhiteSpace($cur)) {
    Set-Item -Path ("env:" + $Name) -Value $Value
  }
}

function Select-MainMenu {
  Write-Host ""
  Write-Host "=== DEPLOY WINDOWS (ABSENTA) ==="
  Write-Host "1) Deploy/Update SINGLE (postgres+redis+api+workers)"
  Write-Host "2) Deploy/Update MULTI (mode multi-node)"
  Write-Host "3) Status SINGLE"
  Write-Host "4) Status MULTI"
  Write-Host "5) Logs API"
  Write-Host "6) Restart SINGLE"
  Write-Host "7) Restart MULTI"
  Write-Host "8) Stop SINGLE"
  Write-Host "9) Stop MULTI"
  Write-Host "10) Cleanup disk docker (prune)"
  Write-Host "0) Keluar"
  $opt = Read-Host "Pilih"
  switch ("$opt") {
    "1" { return @{ Action = "deploy"; Mode = "single" } }
    "2" { return @{ Action = "deploy"; Mode = "multi" } }
    "3" { return @{ Action = "status"; Mode = "single" } }
    "4" { return @{ Action = "status"; Mode = "multi" } }
    "5" { return @{ Action = "logs_api"; Mode = "" } }
    "6" { return @{ Action = "restart"; Mode = "single" } }
    "7" { return @{ Action = "restart"; Mode = "multi" } }
    "8" { return @{ Action = "stop"; Mode = "single" } }
    "9" { return @{ Action = "stop"; Mode = "multi" } }
    "10" { return @{ Action = "cleanup"; Mode = "" } }
    "0" { exit 0 }
    default { return @{ Action = "deploy"; Mode = "multi" } }
  }
}

$isInteractive = (-not $NonInteractive) -and [Environment]::UserInteractive -and ($Host.UI -ne $null) -and ($Host.UI.RawUI -ne $null)
if ([string]::IsNullOrWhiteSpace($Action) -and $isInteractive) {
  $picked = Select-MainMenu
  $Action = $picked.Action
  if ([string]::IsNullOrWhiteSpace($Mode)) { $Mode = $picked.Mode }
}
if ([string]::IsNullOrWhiteSpace($Action)) { $Action = "deploy" }

if (($Action -in @("deploy", "status", "restart", "stop")) -and [string]::IsNullOrWhiteSpace($Mode)) {
  if ($isInteractive) {
    $Mode = Prompt-Text -Label "Pilih mode (single/multi)" -DefaultValue "multi"
  } else {
    $Mode = "multi"
  }
}
if (($Action -in @("deploy", "status", "restart", "stop")) -and ($Mode -ne "single" -and $Mode -ne "multi")) {
  Write-Error "Mode tidak valid: $Mode. Gunakan: single | multi"
  exit 1
}

if ([string]::IsNullOrWhiteSpace($ComposeFile)) {
  if ($Mode -eq "single") { $ComposeFile = Join-Path $scriptDir "docker-compose.windows.single.yml" }
  if ($Mode -eq "multi") { $ComposeFile = Join-Path $scriptDir "docker-compose.windows.yml" }
}

Write-Host ("=== Absenta Deployment (Windows) ===")
Write-Host ("Action: " + $Action + ($(if ($Mode -ne "") { ", Mode: " + $Mode } else { "" })))

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

if (($Action -in @("deploy", "status", "restart", "stop")) -and (-not (Test-Path $ComposeFile))) {
  Write-Error "File compose tidak ditemukan: $ComposeFile"
  exit 1
}

if ($Action -eq "logs_api") {
  try {
    docker logs absenta-backend-api --tail 200 | Write-Host
  } catch {
    Write-Warning "Gagal mengambil log API."
  }
  exit 0
}

if ($Action -eq "cleanup") {
  if ($isInteractive) {
    $ok = Prompt-YesNo -Label "Ini akan menjalankan docker system prune -af dan docker volume prune -f. Lanjutkan?" -DefaultYes $false
    if (-not $ok) { exit 0 }
  }
  try { docker system prune -af | Write-Host } catch { Write-Warning "docker system prune gagal." }
  try { docker volume prune -f | Write-Host } catch { Write-Warning "docker volume prune gagal." }
  exit 0
}

if ($Action -eq "status") {
  Write-Host "-> Status containers"
  try {
    docker compose -f "$ComposeFile" ps | Write-Host
  } catch {
    try { docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | Write-Host } catch {}
  }
  exit 0
}

if ($Action -eq "stop") {
  Write-Host "-> Stop & remove containers (down)"
  docker compose -f "$ComposeFile" down | Write-Host
  exit 0
}

if ($Action -eq "restart") {
  Write-Host "-> Restart containers"
  docker compose -f "$ComposeFile" restart | Write-Host
  exit 0
}

if ($Action -eq "deploy") {
  $stackDownFirst = $true
  $noCache = $true
  if ($isInteractive) {
    $stackDownFirst = Prompt-YesNo -Label "Stop & remove containers dulu (down)?" -DefaultYes $true
    $noCache = Prompt-YesNo -Label "Build images pakai --no-cache?" -DefaultYes $true
  }

  try {
    $composeDir = Split-Path -Parent $ComposeFile
    $envDir = Resolve-Path (Join-Path $composeDir "..\env")
    $envCommonPath = Join-Path $envDir "env.common"
    $defaults = Read-EnvFile -Path $envCommonPath

    $defaultPublicAppUrl = $(if ($env:PUBLIC_APP_URL) { $env:PUBLIC_APP_URL } elseif ($defaults.ContainsKey("PUBLIC_APP_URL")) { $defaults["PUBLIC_APP_URL"] } else { "" })
    $defaultInvoiceBaseUrl = $(if ($env:PUBLIC_INVOICE_BASE_URL) { $env:PUBLIC_INVOICE_BASE_URL } elseif ($defaults.ContainsKey("PUBLIC_INVOICE_BASE_URL")) { $defaults["PUBLIC_INVOICE_BASE_URL"] } else { "" })

    if ([string]::IsNullOrWhiteSpace($defaultInvoiceBaseUrl)) { $defaultInvoiceBaseUrl = $defaultPublicAppUrl }

    $guessHost = Get-HostFromUrl -Value $defaultPublicAppUrl
    $defaultMainDomain = $(if ($env:MAIN_DOMAIN) { $env:MAIN_DOMAIN } elseif ($defaults.ContainsKey("MAIN_DOMAIN")) { $defaults["MAIN_DOMAIN"] } elseif ($guessHost) { $guessHost } else { "" })

    Set-EnvIfEmpty -Name "PUBLIC_APP_URL" -Value $defaultPublicAppUrl
    Set-EnvIfEmpty -Name "PUBLIC_INVOICE_BASE_URL" -Value $defaultInvoiceBaseUrl
    Set-EnvIfEmpty -Name "MAIN_DOMAIN" -Value $defaultMainDomain

    if ($isInteractive) {
      $env:PUBLIC_APP_URL = Prompt-Text -Label "PUBLIC_APP_URL (domain/app url)" -DefaultValue $env:PUBLIC_APP_URL
      $env:PUBLIC_INVOICE_BASE_URL = Prompt-Text -Label "PUBLIC_INVOICE_BASE_URL" -DefaultValue $(if ($env:PUBLIC_INVOICE_BASE_URL) { $env:PUBLIC_INVOICE_BASE_URL } else { $env:PUBLIC_APP_URL })
      $env:MAIN_DOMAIN = Prompt-Text -Label "MAIN_DOMAIN (untuk CORS subdomain)" -DefaultValue $(if ($env:MAIN_DOMAIN) { $env:MAIN_DOMAIN } else { (Get-HostFromUrl -Value $env:PUBLIC_APP_URL) })
    }
  } catch {}

  if ($Mode -eq "single" -and $isInteractive) {
    $env:POSTGRES_DB = Prompt-Text -Label "POSTGRES_DB" -DefaultValue ($(if ($env:POSTGRES_DB) { $env:POSTGRES_DB } else { "absensi" }))
    $env:POSTGRES_USER = Prompt-Text -Label "POSTGRES_USER" -DefaultValue ($(if ($env:POSTGRES_USER) { $env:POSTGRES_USER } else { "postgres" }))
    $env:POSTGRES_PASSWORD = Prompt-Text -Label "POSTGRES_PASSWORD" -DefaultValue ($(if ($env:POSTGRES_PASSWORD) { $env:POSTGRES_PASSWORD } else { "change-me" }))
  }

  if ($Mode -eq "multi") {
    if ($isInteractive -and [string]::IsNullOrWhiteSpace($DatabaseUrl)) {
      $DatabaseUrl = Prompt-Text -Label "DATABASE_URL (kosong = pakai env.database)" -DefaultValue ""
    }
    if (-not [string]::IsNullOrWhiteSpace($DatabaseUrl)) {
      $env:DATABASE_URL = $DatabaseUrl
    }
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

  $env:APP_VERSION = $AppVersion

  if ($stackDownFirst) {
    Write-Host "-> Stop & remove containers (down)"
    docker compose -f "$ComposeFile" down | Write-Host
  }

  if ($noCache) {
    Write-Host "-> Build images (--no-cache)"
    docker compose -f "$ComposeFile" build --no-cache | Write-Host
  } else {
    Write-Host "-> Build images"
    docker compose -f "$ComposeFile" build | Write-Host
  }

  Write-Host "-> Start containers (up -d)"
  try {
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

  if ($Mode -eq "multi") {
    try {
      $composeDir = Split-Path -Parent $ComposeFile
      $envDir = Resolve-Path (Join-Path $composeDir "..\env")
      $envCommon = Join-Path $envDir "env.common"
      $envDb = Join-Path $envDir "env.database"
      $envRedis = Join-Path $envDir "env.redis"
      $envProd = Join-Path $envDir "env.production"

      function Get-ContainerNames {
        try {
          $out = docker ps -a --format "{{.Names}}"
          if (-not $out) { return @() }
          return ($out -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
        } catch {
          return @()
        }
      }

      function Ensure-StandbyContainer {
        param(
          [string]$Name,
          [string]$NodeName,
          [string]$CommandScript
        )
        $names = Get-ContainerNames
        if ($names -contains $Name) {
          try { docker stop $Name | Out-Null } catch {}
          return
        }
        $tmp = Join-Path $env:TEMP ("absenta-worker-env-" + $NodeName + ".env")
        $raw = @()
        if (Test-Path $envCommon) { $raw += Get-Content $envCommon }
        if (Test-Path $envDb) { $raw += Get-Content $envDb }
        if (Test-Path $envRedis) { $raw += Get-Content $envRedis }
        if (Test-Path $envProd) { $raw += Get-Content $envProd }
        $raw += ("NODE_NAME=" + $NodeName)
        $raw | Set-Content -Path $tmp -Encoding ASCII

        docker create --name $Name --restart unless-stopped --network absenta-net --env-file $tmp absenta-backend:latest node $CommandScript | Out-Null
      }

      Ensure-StandbyContainer -Name "absenta-worker-attendance-2" -NodeName "node-attendance" -CommandScript "dist/workers/attendance.worker.js"
      Ensure-StandbyContainer -Name "absenta-worker-attendance-3" -NodeName "node-attendance" -CommandScript "dist/workers/attendance.worker.js"
      Ensure-StandbyContainer -Name "absenta-worker-attendance-4" -NodeName "node-attendance" -CommandScript "dist/workers/attendance.worker.js"
      Ensure-StandbyContainer -Name "absenta-worker-billing-2" -NodeName "node-billing" -CommandScript "dist/workers/billing.worker.js"
      Ensure-StandbyContainer -Name "absenta-worker-notification-2" -NodeName "node-billing" -CommandScript "dist/workers/notification.worker.js"
    } catch {
      Write-Warning "Gagal menyiapkan standby worker containers untuk autoscaling."
    }
  }
}

# Dump logs for exited containers (diagnostic)
try {
  $exited = docker ps -a --filter "status=exited" --filter "name=^absenta-" --format "{{.Names}}"
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
  $ok = $false
  for ($i = 1; $i -le 12; $i++) {
    try {
      $resp = Invoke-WebRequest -Uri "http://localhost:3001/health" -UseBasicParsing -TimeoutSec 5
      Write-Host ("Health code: " + $resp.StatusCode)
      $ok = $true
      break
    } catch {
      Start-Sleep -Seconds 5
    }
  }
  if (-not $ok) {
    Write-Warning "Health check gagal (API mungkin masih starting atau crash). Menampilkan log API:"
    try { docker logs absenta-backend-api --tail 200 | Write-Host } catch {}
  }
} catch {
  Write-Warning "Health check gagal (API mungkin masih starting)."
}

Write-Host "Selesai."
exit 0
