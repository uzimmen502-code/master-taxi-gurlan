# Master Taxi Gurlan — бир Firebase Hosting учун иккита Flutter web:
#   /       → lib/main.dart (фойдаланувчи)
#   /admin/ → lib/main_admin.dart (админ, --base-href /admin/)
#
# Ишлатиш (loyiha ildizidan):
#   powershell -ExecutionPolicy Bypass -File scripts/build_combined_web.ps1
#
# Keyin:
#   firebase deploy --only hosting

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Hosting = Join-Path $Root "build/hosting"
if (Test-Path $Hosting) {
  Remove-Item -Recurse -Force $Hosting
}
New-Item -ItemType Directory -Path $Hosting | Out-Null

Write-Host "==> User web (lib/main.dart)..." -ForegroundColor Cyan
flutter build web -t lib/main.dart --release --pwa-strategy=none
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Copy-Item -Path (Join-Path $Root "build/web/*") -Destination $Hosting -Recurse -Force

Write-Host "==> Admin web (lib/main_admin.dart, base /admin/)..." -ForegroundColor Cyan
flutter build web -t lib/main_admin.dart --release --base-href /admin/ --pwa-strategy=none
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$AdminDir = Join-Path $Hosting "admin"
New-Item -ItemType Directory -Path $AdminDir -Force | Out-Null
Copy-Item -Path (Join-Path $Root "build/web/*") -Destination $AdminDir -Recurse -Force

$KillServiceWorker = @"
self.addEventListener('install', function (event) {
  self.skipWaiting();
});
self.addEventListener('activate', function (event) {
  event.waitUntil((async function () {
    try {
      const keys = await caches.keys();
      await Promise.all(keys.map(function (key) { return caches.delete(key); }));
    } catch (_) {}
    try { await self.registration.unregister(); } catch (_) {}
    const clientsList = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of clientsList) {
      client.navigate(client.url);
    }
  })());
});
"@

# Old Flutter service workers may still be installed in users' browsers.
# Keep a tiny replacement at the same URLs so browsers update, clear old caches,
# unregister the worker, and reload once.
Set-Content -Path (Join-Path $Hosting "flutter_service_worker.js") -Value $KillServiceWorker -Encoding UTF8
Set-Content -Path (Join-Path $AdminDir "flutter_service_worker.js") -Value $KillServiceWorker -Encoding UTF8

$DownloadsSrc = Join-Path $Root "web/downloads"
$DownloadsDst = Join-Path $Hosting "downloads"
if (Test-Path $DownloadsSrc) {
  Write-Host "==> Downloads (APK + QR page)..." -ForegroundColor Cyan
  New-Item -ItemType Directory -Path $DownloadsDst -Force | Out-Null
  Copy-Item -Path (Join-Path $DownloadsSrc "*") -Destination $DownloadsDst -Recurse -Force
}

Write-Host ""
Write-Host "OK: $Hosting" -ForegroundColor Green
Write-Host "  User:  /" -ForegroundColor Green
Write-Host "  Admin: /admin/" -ForegroundColor Green
Write-Host "  APK QR:  /downloads/  (index.html + master-taxi-gurlan-driver.apk)" -ForegroundColor Green
Write-Host "Deploy: firebase deploy --only hosting" -ForegroundColor Yellow
