# Firebase Storage CORS for browser uploads (Flutter web admin).
# Requires: Google Cloud SDK (gsutil), gcloud auth login
# Uses: repo root cors.json
# Newer Firebase projects: only .firebasestorage.app exists (appspot.com may 404).

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$CorsFile = Join-Path $Root "cors.json"

if (-not (Test-Path $CorsFile)) {
    Write-Error "cors.json not found: $CorsFile"
    exit 1
}

if (-not (Get-Command gsutil -ErrorAction SilentlyContinue)) {
    Write-Error "gsutil not found. Install Google Cloud SDK and add to PATH."
    exit 1
}

$buckets = @(
    "gs://master-taxi-gurlan.firebasestorage.app",
    "gs://master-taxi-gurlan.appspot.com"
)

foreach ($b in $buckets) {
    Write-Host ""
    Write-Host "CORS apply: $CorsFile -> $b" -ForegroundColor Cyan
    cmd /c "gsutil cors set `"$CorsFile`" `"$b`""
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Skipped (404 or no access). OK if legacy appspot.com does not exist." -ForegroundColor Yellow
        continue
    }
    Write-Host "Current CORS for $b" -ForegroundColor Green
    cmd /c "gsutil cors get `"$b`""
}

Write-Host ""
Write-Host "Done. CORS on firebasestorage.app is enough if appspot was skipped." -ForegroundColor Green
