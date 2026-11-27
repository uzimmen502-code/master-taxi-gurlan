# AVA - Shaharlararo taksi auditi: production deploy (egasi ishga tushiradi)
# Branch: fix/courier-audit-2026-10, worktree: D:\projects\ava_wt_courier_audit
# TARTIB: 1) functions:default (nom bilan)  2) Firestore RULES (ALOHIDA)   [indeks - README, egasi qarori]
# Ilova (APK/web) alohida: Flutter tarmog'i fix/courier-audit-flutter (qarang README_uz.md, "Intercity").

$ErrorActionPreference = 'Stop'
$wt      = 'D:\projects\ava_wt_courier_audit'
$cfg     = "$wt\firebase.json"
$project = 'master-taxi-gurlan'
$lastCodeCommit = 'aea0d8d'   # oxirgi intercity kod commiti (npm skriptlari)

Set-Location $wt
if ((git branch --show-current) -ne 'fix/courier-audit-2026-10') { throw 'Noto''g''ri branch' }
git merge-base --is-ancestor $lastCodeCommit HEAD
if ($LASTEXITCODE -ne 0) { throw "HEAD $lastCodeCommit ni o'z ichiga olmaydi" }
if (git status --porcelain -- functions functions_demand firestore.rules) { throw 'Worktree toza emas' }
Write-Host "HEAD = $(git rev-parse --short HEAD)" -ForegroundColor Cyan

function Confirm-Step($text) { if ((Read-Host "$text  [y/N]") -ne 'y') { throw 'Bekor qilindi' } }

# 1) functions:default - nom bilan (to'liq functions:default deploy QILINMASIN)
$def = @('updateIntercityDriverRating','publishTaxiTrip','rescheduleTaxiTrip','cancelTaxiTrip','intercityCancelBooking',
         'expirePendingTrips','autoUpdateDepartureTime','intercityCreateBooking','intercityCompleteBooking')
Confirm-Step "1/2 functions:default ($($def.Count) ta)"
firebase deploy --only (($def | ForEach-Object { "functions:default:$_" }) -join ',') --project $project --config $cfg

# 2) RULES - alohida buyruq. OLDIN: jonli ruleset == bizning faylning oldingi versiyasi ekanini tekshiring
#    (gcloud auth print-access-token + firebaserules API; farq FAQAT intercityPublishGate* va intercity_drivers update bo'lishi kerak).
Confirm-Step '2/2 Firestore RULES (H1: isActive:true / billingTripId faqat published taxi_trips bilan)'
firebase deploy --only firestore:rules --project $project --config $cfg

Write-Host 'TAYYOR. README dagi Intercity tekshiruvlarini bajaring.' -ForegroundColor Green
