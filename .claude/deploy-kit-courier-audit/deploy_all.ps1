# AVA - kuryer/logistika auditi tuzatishlari: production deploy (egasi ishga tushiradi)
# Branch: fix/courier-audit-2026-10, worktree: D:\projects\ava_wt_courier_audit
# Tartib: 1) Firestore rules (ALOHIDA)  2) functions:default (nom bilan)  3) functions:demand (nom bilan)
# Har qadamdan oldin to'xtab tasdiq so'raydi. Hech narsa --force bilan emas.

$ErrorActionPreference = 'Stop'
$wt      = 'D:\projects\ava_wt_courier_audit'
$cfg     = "$wt\firebase.json"
$project = 'master-taxi-gurlan'
$lastCodeCommit = '38038ef'   # oxirgi kod commiti (L10); kit commiti undan keyin

Set-Location $wt

# --- Old tekshiruvlar -------------------------------------------------------
if ((git branch --show-current) -ne 'fix/courier-audit-2026-10') { throw 'Noto''g''ri branch' }
git merge-base --is-ancestor $lastCodeCommit HEAD
if ($LASTEXITCODE -ne 0) { throw "HEAD $lastCodeCommit ni o'z ichiga olmaydi" }
if (git status --porcelain -- functions functions_demand firestore.rules) { throw 'Worktree toza emas (functions/functions_demand/firestore.rules)' }
Write-Host "HEAD = $(git rev-parse --short HEAD)  (kod: $lastCodeCommit)" -ForegroundColor Cyan

function Confirm-Step($text) {
  $a = Read-Host "$text  [y/N]"
  if ($a -ne 'y') { throw 'Bekor qilindi' }
}

# --- 1) RULES (functions bilan birga EMAS) -----------------------------------
# Jonli ruleset 0c2154c2-5a2d-4353-95be-738494b4feed == cecf2ae dagi firestore.rules (tekshirilgan).
# Bizning farq: faqat +20/-1 qator (delivery_routes status, demand_matches status).
Confirm-Step '1/3 Firestore RULES deploy (faqat rules)'
firebase deploy --only firestore:rules --project $project --config $cfg

# --- 2) functions:default (nom bilan; FULL deploy EMAS - branchlar aralash) -------
$def = @(
  'courierSubmitPayment','courierMarkPicked','courierMarkArrived','courierRecoverOrphanRoute',
  'courierFinalizeCollection','courierCashPendingSweep',
  'placeCarpetWashOrder','courierMarkCarpetArrived','courierMarkCarpetPickedUp','courierMarkCarpetDelivered',
  'placeAgroPickupOrder','courierMarkAgroPickupArrived','courierMarkAgroPickedUp',
  'onDeliveryRouteCreate','onDeliveryRouteAssign',
  'courierCompleteRestaurantDelivery','restaurantAcceptOrder','restaurantMarkReady',
  'relayEscrowReconcile','onLogisticsCustodyEvent'
)
$onlyDef = ($def | ForEach-Object { "functions:default:$_" }) -join ','
Confirm-Step "2/3 functions:default ($($def.Count) ta funksiya)"
firebase deploy --only $onlyDef --project $project --config $cfg

# --- 3) functions:demand (nom bilan; discovery vaqtini oshiramiz) ----------------
$env:FUNCTIONS_DISCOVERY_TIMEOUT = '120'
$dem = @(
  'quoteLogisticsOrder','createLogisticsOrder','acceptLeg','scanHandover','confirmDelivery',
  'cancelLogisticsOrder','adminUpsertLogisticsTariff','adminActivateLogisticsTariff',
  'adminPlanShipmentRoute','adminReactivateLeg','legChainSweeper'
)
$onlyDem = ($dem | ForEach-Object { "functions:demand:$_" }) -join ','
Confirm-Step "3/3 functions:demand ($($dem.Count) ta funksiya)"
firebase deploy --only $onlyDem --project $project --config $cfg

Write-Host 'TAYYOR. Endi README dagi "Deploydan keyin tekshirish" bandini bajaring.' -ForegroundColor Green
