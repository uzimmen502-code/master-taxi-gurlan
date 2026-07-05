# Firebase Hosting — privacy + delete-account sahifalarini deploy qilish.
# Oldin bir marta: firebase login --no-localhost  (yourmastertaxi@gmail.com)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Hosting = Join-Path $Root "build/hosting"
if (-not (Test-Path $Hosting)) {
  Write-Host "build/hosting yo'q — avval web build:" -ForegroundColor Yellow
  Write-Host "  powershell -ExecutionPolicy Bypass -File scripts/build_combined_web.ps1"
  exit 1
}

foreach ($f in @("privacy.html", "delete-account.html")) {
  $src = Join-Path $Root "web/$f"
  if (Test-Path $src) {
    Copy-Item $src (Join-Path $Hosting $f) -Force
    Write-Host "Synced $f" -ForegroundColor Green
  }
}

$privacyDir = Join-Path $Root "web/privacy/index.html"
if (Test-Path $privacyDir) {
  $dst = Join-Path $Hosting "privacy"
  New-Item -ItemType Directory -Path $dst -Force | Out-Null
  Copy-Item $privacyDir (Join-Path $dst "index.html") -Force
}

Write-Host "Deploying to master-taxi-gurlan..." -ForegroundColor Cyan
firebase deploy --only hosting
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "OK:" -ForegroundColor Green
Write-Host "  https://master-taxi-gurlan.web.app/privacy.html"
Write-Host "  https://master-taxi-gurlan.web.app/delete-account.html"
