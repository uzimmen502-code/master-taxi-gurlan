# AVA - D1 "Posilka yoqoldi": production deploy (2-bosqich, egasi ishga tushiradi)
# Faqat functions. Rules / indekslar / migratsiya KERAK EMAS.
# TARTIB MUHIM: avval default (us-central1), keyin demand (europe-west1).
# DIQQAT: declaredValue endi MAJBURIY (quote/create). Flutter ilovasi hali yangilanmagan:
#   eski ilovada maydon bosh bolsa umumiy xato chiqadi. Logistika hozir yopiq/internal (faqat testerlar, WEB).

$ErrorActionPreference = 'Stop'
$wt      = 'D:\projects\ava_wt_courier_audit'
$cfg     = "$wt\firebase.json"
$project = 'master-taxi-gurlan'
$lastCodeCommit = '76a9ec3'

Set-Location $wt
if ((git branch --show-current) -ne 'fix/courier-audit-2026-10') { throw 'Noto''g''ri branch' }
git merge-base --is-ancestor $lastCodeCommit HEAD
if ($LASTEXITCODE -ne 0) { throw "HEAD $lastCodeCommit ni o'z ichiga olmaydi" }
if (git status --porcelain -- functions functions_demand firestore.rules) { throw 'Worktree toza emas' }
Write-Host "HEAD = $(git rev-parse --short HEAD)" -ForegroundColor Cyan

function Confirm-Step($text) { if ((Read-Host "$text  [y/N]") -ne 'y') { throw 'Bekor qilindi' } }

# 1) default codebase (nom bilan; to'liq functions:default deploy QILINMASIN)
$def = @('adminRecordLostParcelPayment','onLogisticsShipmentUpdate','relayEscrowReconcile','onLogisticsCustodyEvent','fundShipmentEscrow')
Confirm-Step "1/2 functions:default ($($def.Count) ta)"
firebase deploy --only (($def | ForEach-Object { "functions:default:$_" }) -join ',') --project $project --config $cfg

# 2) demand codebase (core/logistics.js ni ishlatadigan barcha logistika funksiyalari, nom bilan)
$env:FUNCTIONS_DISCOVERY_TIMEOUT = '120'
$dem = @('adminMarkShipmentLost','quoteLogisticsOrder','createLogisticsOrder','acceptLeg','scanHandover','confirmDelivery',
         'cancelLogisticsOrder','adminUpsertLogisticsTariff','adminActivateLogisticsTariff','adminPlanShipmentRoute',
         'adminReactivateLeg','legChainSweeper')
Confirm-Step "2/2 functions:demand ($($dem.Count) ta)"
firebase deploy --only (($dem | ForEach-Object { "functions:demand:$_" }) -join ',') --project $project --config $cfg

Write-Host 'TAYYOR. README dagi D1 tekshiruvlarini bajaring.' -ForegroundColor Green
