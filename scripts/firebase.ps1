# Firebase CLI — Windows SSL + keep-alive fix.
# Ishlatish:
#   .\scripts\firebase.ps1 login --reauth --no-localhost
#   .\scripts\firebase.ps1 deploy --only firestore:indexes

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$noKeepAlive = Join-Path $PSScriptRoot 'no-keepalive.cjs'

$env:NODE_OPTIONS = "--use-system-ca --require $noKeepAlive"

Set-Location $repoRoot

if ($args.Count -eq 0) {
  firebase --help
  exit $LASTEXITCODE
}

firebase @args
exit $LASTEXITCODE
