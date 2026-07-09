# Firebase login — SSL + keep-alive tuzatishlari bilan.
# MUHIM: URL ni faqat shu kompyuter brauzerida oching (telefonda emas).

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Write-Host ''
Write-Host '=== Firebase login ===' -ForegroundColor Cyan
Write-Host 'Node:' (node -v) '  Firebase CLI:' (firebase --version)
Write-Host ''
Write-Host 'Qoidalar:' -ForegroundColor Yellow
Write-Host '  1) URL ni shu PC brauzerida oching (Chrome/Edge)'
Write-Host '  2) Eski login oynalarini yoping — faqat YANGI URL'
Write-Host '  3) Kodni 2 daqiqa ichida terminalga yoping'
Write-Host '  4) VPN/proxy bo''lsa o''chiring'
Write-Host ''

& "$PSScriptRoot\firebase.ps1" logout 2>$null
& "$PSScriptRoot\firebase.ps1" login --reauth --no-localhost

if ($LASTEXITCODE -ne 0) {
  Write-Host ''
  Write-Host 'Login yana muvaffaqiyatsiz.' -ForegroundColor Red
  Write-Host ''
  Write-Host 'Zaxira (login shart emas) — index deploy:' -ForegroundColor Yellow
  Write-Host '  .\scripts\deploy-firestore-indexes.ps1'
  Write-Host '  yoki Firebase Console → Firestore → Indexes'
  Write-Host ''
  Write-Host 'CLI yangilash (tavsiya):' -ForegroundColor Yellow
  Write-Host '  npm install -g firebase-tools@latest'
  exit 1
}

Write-Host ''
& "$PSScriptRoot\firebase.ps1" login:list
Write-Host ''
Write-Host 'OK. Keyin:' -ForegroundColor Green
Write-Host '  .\scripts\firebase.ps1 deploy --only firestore:indexes'
