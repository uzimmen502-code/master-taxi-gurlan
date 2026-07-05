# Admin Web Panel + Analytics

Web-only entry `lib/main_admin.dart` (built `-t lib/main_admin.dart --base-href /admin/`). Schema: `mem:firestore_schema`. CFs/RBAC: `mem:cloud_functions`.

## Entry & shell
- `main_admin.dart`: Firebase init + `installFirestoreCrashGuard()` + `Settings(persistenceEnabled:false)` + AdminAuthService.restoreSession + AdminNewsReadService.init. MultiProvider (~20 repos). `_AuthGate` → AdminShell | AdminLoginScreen. Theme `AppTheme.adminWeb`.
- `screens/admin_shell.dart`: `import 'dart:html'` (web-only, lint-ignored). `_Sidebar` 240/92px or Drawer<700px. Section dispatch by `section.label` string match; pages lazy-cached in `_pageCache` (state persists across tabs). Mobile home btn → `html.window.location.href='/'`; `navigateSameOriginPath('/')`.

## Sidebar sections (label → screen)
Monitoring Center→MonitoringCenterScreen(embedded) · Буюртмалар→AdminOrdersScreen · Gilam yuvish→CarpetWashAdminScreen · Sut qabul→AgroPickupAdminScreen · Курьer→CourierAdminScreen · Курьerлар→CourierManagementScreen · Иш топ→JobsModerationScreen · **Onlayn BOZOR→MarketModerationScreen** · ❤️ Танишув→DatingModerationScreen · Хабарлар→AdminNewsListScreen · Бегущая строка→AdminHomeTickerScreen · Буюртма хабар→AdminOrderNewsListScreen · Сотиш таклифлари→SellSubmissionsAdminScreen · Маҳсулотлар→ProductsManagerScreen · Харид нархлари→ProcurementPricesScreen · 🚕 Такси нархи→TaxiPriceScreen · Омбор→WarehouseStockScreen · Ҳайдовчи аризалари→DriverApplicationsScreen · Туғилган кун→IdentityApprovalsScreen · Код сўровлари→PendingCodesScreen · Маршрут→MarshrutAdminScreen · Shaharlararo→IntercityAdminScreen · Фoydalanuvchilar→UsersDevicesScreen · Risk review→RiskReviewScreen · Аномалия созламалари→AnomalySettingsScreen · Молия→PayoutManagementScreen · Finance Center→FinanceCenterScreen · Birthday bonus→BirthdayBonusScreen · Dispatch history→MarshrutDispatchHistoryScreen · Чат қўллаб-қувватlash→ChatSupportScreen.
- NOT wired into shell: entertainment_catalog_tab.dart (embedded/sub-tabs). jobs_complaints_tab.dart embedded in JobsModerationScreen.
- Badge streams: Иш топ=pending ads filtered to jobs-board types only; **Onlayn BOZOR=inactive cheap_product count**; others unchanged.

## Auth / RBAC
- `admin_auth_service.dart`: trusted phone `998912778777` → CF adminWebSignIn (SMS-less custom token); others → Firebase Phone OTP; PIN → CF adminWebSignInWithCode. Role gate `_isAdminRole` ∈ {admin,superadmin,dispatcher}. Persists prefs user_role/phone/name.
- **Иш топ writes**: `AdminJobsService` → CF `adminDeleteJobAd`, `adminUpdateJobAdStatus`, `adminUpdateJobAd`, `adminResolveJobComplaint` (Firestore rules `isAdmin()` unreliable with admin custom token).
- **Onlayn BOZOR writes**: `AdminMarketService` → CF `adminDeleteMarketAd`, `adminUpdateMarketAdStatus`, `adminUpdateMarketAd`.
- `admin_role_service.dart`: setUserRole → CF setUserRoleByAdmin.
- CF guard `assertAdmin`. Role sets: general admin {admin,superadmin,dispatcher}; finance ops {admin,superadmin,finance}; read-only ledger/audit {admin,superadmin,finance,auditor}.

## Jobs + Market moderation
- `jobs_moderation_screen.dart` + `jobs_ad_edit_dialog.dart` + `jobs_complaints_tab.dart` — jobs board only (`JobsRepository.watchAllForAdmin` excludes cheap_product).
- **`market_moderation_screen.dart` + `market_ad_edit_dialog.dart`** — cheap_product only (`AdsRepository.watchAllForAdmin`). Actions: activate/deactivate, edit, delete (CF deletes Storage images too).

## Gotchas
- Build: `flutter build web --release -t lib/main_admin.dart --base-href /admin/`; combined deploy `scripts/build_combined_web.ps1` → `firebase deploy --only hosting` (/=user, /admin/=admin).
- Deploy CF when adding/changing admin callable functions.
- `dart:html` only in admin_shell.dart + same_origin_nav_web.dart + firestore_crash_guard_web.dart — never import into mobile build.
- Firestore web "Unexpected state" worked around by installFirestoreCrashGuard() + persistence disabled.