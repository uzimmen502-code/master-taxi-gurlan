# ava_gurlan (brand: AVA Gurlan)

Flutter multi-service app (taxi: local + marshrut + intercity; delivery/food/bread) with Firebase backend. Brand name shown is "AVA Gurlan"; pubspec `name: ava_gurlan` (renamed from `master_taxi_gurlan` 2026-06). Windows folder `C:\projects\ava_gurlan`, Serena project_name `ava_gurlan`, Android applicationId `uz.ava.gurlan` (all renamed 2026-06). Legacy `com.example.master_taxi_gurlan` kept only as a google-services.json client for migration.

## Source map
- `lib/` — Flutter app (Dart)
  - `lib/main.dart` user app entry; `lib/main_admin.dart` web admin entry (built with `--base-href /admin/`)
  - `lib/features/` feature modules (home, driver_home, local_taxi, marshrut, food, bread, intercity, admin_web, ...)
  - `lib/services/` CF wrappers + device services (balance_service, settlement_service, deferred_settlement_queue, ...)
  - `lib/repositories/` Firestore data access; `lib/models/` data models; `lib/core/` theme + utils
- `functions/` Firebase Cloud Functions (Node.js). Single large `index.js` + `settlement_ledger.js`. `functions/tools/` one-off scripts + self-cleaning E2E tests. Needs `service-account.json` for tools.
- `firestore.rules` security rules; `scripts/build_combined_web.ps1` builds user+admin web into `build/hosting`; `docs/` design docs.

## Project-wide invariants
- Money: `users/{uid}.bonusBalance` is a PROJECTION of ledger `passenger_credit:{uid}`. Every bonus mutation goes through the ledger mirror. See `mem:settlement_ledger`.
- CF region `us-central1`; Firestore region `eur3` (cross-region trigger warnings are expected, ignore).
- Admin SDK in CFs bypasses `firestore.rules`; ledger collections are CF-only writes.

## Backend / cross-cutting memories
- Double-entry money engine (float, trip settlement, deferred, spendCredit, finance center): `mem:settlement_ledger`
- All 111 Cloud Functions grouped by domain (grep `^exports.NAME` to jump): `mem:cloud_functions`
- Every Firestore collection + access rules + composite indexes + rules helpers: `mem:firestore_schema`
- Languages/frameworks/pkgs: `mem:tech_stack`
- Commands incl. Windows/PowerShell specifics: `mem:suggested_commands`
- Code style/naming/RBAC/idempotency patterns: `mem:conventions`
- What to run before calling a task done: `mem:task_completion`

## Feature module maps (files + collections + flows + gotchas per module)
- Taxi: local + marshrut (flat route price, system queue) + intercity + driver_home/schedule: `mem:modules/taxi`
- Commerce/delivery: food + bread + orders + courier (placeOrderPostPaid, inventory): `mem:modules/commerce`
- Social "Mening yaqinlarim": circles + relatives + dating + global family tree (F1–F5): `mem:modules/social`
- Admin web panel + analytics (main_admin.dart, shell sections, RBAC): `mem:modules/admin_panel`
- Jobs board + cheap-product marketplace (both `ads`) + entertainment: `mem:modules/jobs_ads_entertainment`
- Foundation: home + onboarding (admin-code phone auth) + profile + core services: `mem:modules/foundation`