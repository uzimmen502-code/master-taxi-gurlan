# Admin Web Panel + Analytics

Web-only entry `lib/main_admin.dart` (built `-t lib/main_admin.dart --base-href /admin/`). Schema: `mem:firestore_schema`. CFs/RBAC: `mem:cloud_functions`.

## Entry & shell
- `main_admin.dart`: Firebase init + `installFirestoreCrashGuard()` + `Settings(persistenceEnabled:false)` + AdminAuthService.restoreSession + AdminNewsReadService.init. MultiProvider (~20 repos). `_AuthGate` → AdminShell | AdminLoginScreen. Theme `AppTheme.adminWeb`.
- `screens/admin_shell.dart`: `import 'dart:html'` (web-only, lint-ignored). `_Sidebar` 240/92px or Drawer<700px. Section dispatch by `section.label` string match; pages lazy-cached in `_pageCache` (state persists across tabs). Mobile home btn → `html.window.location.href='/';` `navigateSameOriginPath('/')`.

## Auth / RBAC
- `admin_auth_service.dart`: **any panel-role phone** → CF `adminWebSignIn` (passwordless custom token; no SMS/OTP). PIN → CF `adminWebSignInWithCode` (signs in as trusted operator `998912778777`). Role gate `_isPanelRole` ∈ {admin,superadmin,dispatcher,finance,auditor}. Persists prefs user_role/phone/name. Granting Admin role unlocks passwordless `/admin/` login for that phone.
- **Sidebar access (2026-07)**: `_SectionAccess` — ops (admin/superadmin/dispatcher); finance (finance/auditor/superadmin: Молия+Finance Center); opsAndFinance (Buyurtmalar, Ombor, Харид); users (admin+superadmin); superOnly (Risk, Anomaly). Finance UI label **Buxgalter**.
- **Finance Center (2026-07)**: Назорат + **Cash Exchange** + **Telegram ҳамён** (`WalletBotTab`: top-up/withdraw queues, card settings) + Settlements/Journal/Closing/Exceptions. App withdraw + Telegram top-up panels in user wallet UI. Docs: `docs/telegram_wallet_bot_architecture.md`.
- **Role assign SoD**: ordinary `admin` → only `seller`/`user`; `superadmin` → admin/finance/auditor/seller/superadmin/user. CF `setUserRoleByAdmin` enforces.
- **Иш топ writes**: `AdminJobsService` → CF `adminDeleteJobAd`, `adminUpdateJobAdStatus`, `adminUpdateJobAd`, `adminResolveJobComplaint` (Firestore rules `isAdmin()` unreliable with admin custom token).
- **Onlayn BOZOR writes**: `AdminMarketService` → CF `adminDeleteMarketAd`, `adminUpdateMarketAdStatus`, `adminUpdateMarketAd`.
- `admin_role_service.dart`: setUserRole → CF setUserRoleByAdmin.
- CF guard `assertAdmin`. Role sets: general admin {admin,superadmin,dispatcher}; finance ops {admin,superadmin,finance}; read-only ledger/audit {admin,superadmin,finance,auditor}.

## Jobs + Market moderation
- `jobs_moderation_screen.dart` + `jobs_ad_edit_dialog.dart` + `jobs_complaints_tab.dart` — jobs board only (`JobsRepository.watchAllForAdmin` excludes cheap_product).
- **`market_moderation_screen.dart` + `market_ad_edit_dialog.dart`** — cheap_product only (`AdminMarketService.listAds`). **Table UI** (thumb/title/price/status/seller/views/date/actions); row → detail dialog. Actions: activate/deactivate, edit, delete. **ҚЎЛДА/АВТО** → `adminSetMarketAutoApprove`.

## Gotchas
- Build: `flutter build web --release -t lib/main_admin.dart --base-href /admin/`; combined deploy `scripts/build_combined_web.ps1` → `firebase deploy --only hosting` (/=user, /admin/=admin).
- Deploy CF when adding/changing admin callable functions.
- `dart:html` only in admin_shell.dart + same_origin_nav_web.dart + firestore_crash_guard_web.dart — never import into mobile build.
- Firestore web "Unexpected state" worked around by installFirestoreCrashGuard() + persistence disabled.
