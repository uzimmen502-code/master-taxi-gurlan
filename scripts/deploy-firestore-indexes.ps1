# Firestore index deploy — firebase login siz (service account).
# 403 bo'lsa: IAM ga Cloud Datastore Index Admin qo'shing.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

node --use-system-ca functions/tools/deploy-firestore-indexes.js
exit $LASTEXITCODE
