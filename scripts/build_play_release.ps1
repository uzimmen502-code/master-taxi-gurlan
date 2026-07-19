# AVA Zona — Google Play App Bundle build
# Ishlatish: powershell -ExecutionPolicy Bypass -File scripts/build_play_release.ps1

$ErrorActionPreference = "Stop"
$ProjectDir = "C:\projects\ava_gurlan"
$AabSource  = "$ProjectDir\build\app\outputs\bundle\release\app-release.aab"
$Desktop    = [Environment]::GetFolderPath("Desktop")

Set-Location $ProjectDir

if (-not (Test-Path "C:\projects\key.properties")) {
  throw "key.properties topilmadi: C:\projects\key.properties"
}
if (-not (Test-Path "C:\projects\release.keystore")) {
  throw "release.keystore topilmadi: C:\projects\release.keystore"
}

$versionLine = (Select-String -Path "pubspec.yaml" -Pattern "^version:").Line.Trim()
Write-Host "Versiya: $versionLine" -ForegroundColor Cyan

Write-Host "`n=== flutter clean ===" -ForegroundColor Cyan
flutter clean

Write-Host "`n=== flutter pub get ===" -ForegroundColor Cyan
flutter pub get

Write-Host "`n=== flutter build appbundle --release ===" -ForegroundColor Cyan
flutter build appbundle --release
if ($LASTEXITCODE -ne 0) { throw "appbundle build failed" }

if (-not (Test-Path $AabSource)) {
  throw "AAB topilmadi: $AabSource"
}

$ver = ($versionLine -replace "version:\s*", "") -replace "\+", "_"
$AabDest = Join-Path $Desktop "ava-gurlan-$ver.aab"
Copy-Item $AabSource $AabDest -Force

$sizeMb = [math]::Round((Get-Item $AabDest).Length / 1MB, 1)
Write-Host "`n=== TAYYOR ===" -ForegroundColor Green
Write-Host "AAB: $AabDest ($sizeMb MB)"
Write-Host "Play Console ga shu faylni yuklang."
