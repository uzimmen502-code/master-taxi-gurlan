# Master Taxi Gurlan — Release Build Script
# Run from: C:\projects\ava_gurlan

param(
  [switch]$SkipClean,
  [switch]$SkipDeploy
)

$ErrorActionPreference = "Stop"
$ProjectDir = "C:\projects\ava_gurlan"
$ApkSource  = "$ProjectDir\build\app\outputs\flutter-apk\app-release.apk"
$ApkDest    = "$ProjectDir\web\downloads\master-taxi-gurlan.apk"

Set-Location $ProjectDir

Write-Host "`n=== 1. Flutter clean ===" -ForegroundColor Cyan
if (-not $SkipClean) {
  flutter clean
  if ($LASTEXITCODE -ne 0) { throw "flutter clean failed" }
} else {
  Write-Host "Skipped (--SkipClean)" -ForegroundColor Yellow
}

Write-Host "`n=== 2. Flutter pub get ===" -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }

Write-Host "`n=== 3. Build release APK ===" -ForegroundColor Cyan
flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed" }

Write-Host "`n=== 4. Verify APK ===" -ForegroundColor Cyan
if (-not (Test-Path $ApkSource)) {
  throw "APK not found: $ApkSource"
}
$apkSize = (Get-Item $ApkSource).Length / 1MB
Write-Host "APK size: $([math]::Round($apkSize, 1)) MB"
if ($apkSize -lt 30) {
  throw "APK too small ($apkSize MB) — possibly corrupted"
}

Write-Host "`n=== 5. Copy APK to downloads ===" -ForegroundColor Cyan
Copy-Item $ApkSource $ApkDest -Force
Write-Host "Copied to: $ApkDest"

Write-Host "`n=== 6. Build web ===" -ForegroundColor Cyan
powershell -ExecutionPolicy Bypass `
  -File "$ProjectDir\scripts\build_combined_web.ps1"

Write-Host "`n=== 7. Firebase deploy ===" -ForegroundColor Cyan
if (-not $SkipDeploy) {
  firebase deploy --only hosting
  if ($LASTEXITCODE -ne 0) { throw "firebase deploy failed" }
} else {
  Write-Host "Skipped (--SkipDeploy)" -ForegroundColor Yellow
}

Write-Host "`n=== BUILD COMPLETE ===" -ForegroundColor Green
Write-Host "APK URL: https://master-taxi-gurlan.web.app/downloads/master-taxi-gurlan.apk"
Write-Host "APK size: $([math]::Round($apkSize, 1)) MB"
Write-Host "Built at: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
