Param(
  [switch]$SkipRestart
)

$ErrorActionPreference = "Stop"
Write-Host "=== Enable WSL2 & Virtualization Features (Admin Required) ==="

function Require-Admin {
  $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Script ini harus dijalankan sebagai Administrator (Run as Administrator)."
    exit 1
  }
}

Require-Admin

Write-Host "-> Mengaktifkan VirtualMachinePlatform ..."
& dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart

Write-Host "-> Mengaktifkan Microsoft-Windows-Subsystem-Linux ..."
& dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart

Write-Host "-> Mengatur WSL default version ke 2 ..."
try {
  wsl --set-default-version 2 | Write-Host
} catch {
  Write-Warning "WSL CLI belum tersedia atau gagal set default version. Lanjutkan setelah reboot."
}

Write-Host "-> Update kernel WSL (opsional, jika tersedia)..."
try {
  wsl --update | Write-Host
} catch {
  Write-Warning "WSL update gagal atau belum tersedia. Ini dapat dilakukan setelah reboot."
}

if (-not $SkipRestart) {
  Write-Host "Reboot direkomendasikan agar perubahan fitur aktif penuh."
}

Write-Host "Selesai."
exit 0
