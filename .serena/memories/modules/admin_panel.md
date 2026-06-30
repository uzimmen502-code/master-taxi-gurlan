# Admin Web Panel + Analytics

Web-only entry `lib/main_admin.dart` (built `-t lib/main_admin.dart --base-href /admin/`). Schema: `mem:firestore_schema`. CFs/RBAC: `mem:cloud_functions`.

## Entry & shell
- `main_admin.dart`: Firebase init + `installFirestoreCrashGuard()` + `Settings(persistenceEnabled:false)` + AdminAuthService.restoreSession + AdminNewsReadService.init. MultiProvider (~18 repos). `_AuthGate` → AdminShell | AdminLoginScreen. Theme `AppTheme.adminWeb`.
- `screens/admin_shell.dart`: `import 'dart:html'` (web-only, lint-ignored). `_Sidebar` 240/92px or Drawer<700px. Section dispatch by `section.label` string match; pages lazy-cached in `_pageCache` (state persists across tabs). Mobile home btn → `html.window.location.href='/'`; `navigateSameOriginPath('/')`.

## Sidebar sections (label → screen)
Monitoring Center→MonitoringCenterScreen(embedded) · Буюртмалар→AdminOrdersScreen · 🛵 Kuryer buyurtmalari→CourierOrdersAdminScreen · Курьер→CourierAdminScreen · Курьерлар→CourierManagementScreen · Иш топ→JobsModerationScreen · ❤️ Танишув→DatingModerationScreen · Хабарлар→AdminNewsListScreen · Бегущая строка→AdminHomeTickerScreen · Буюртма хабар→AdminOrderNewsListScreen · Сотиш таклифлари→SellSubmissionsAdminScreen · Маҳсулотлар→ProductsManagerScreen · Харид нархлари→ProcurementPricesScreen · 🚕 Такси нархи→TaxiPriceScreen · Омбор→WarehouseStockScreen · Ҳайдовчи аризалари→DriverApplicationsScreen · Туғилган кун→IdentityApprovalsScreen · Код сўровлари→PendingCodesScreen · Маршрут→MarshrutAdminScreen · Shaharlararo→IntercityAdminScreen · Фойдаланувчилар→UsersDevicesScreen · Risk review→RiskReviewScreen · Аномалия созламалари→AnomalySettingsScreen · Молия→PayoutManagementScreen · Finance Center→FinanceCenterScreen · Birthday bonus→BirthdayBonusScreen · Dispatch history→MarshrutDispatchHistoryScreen · Чат қўллаб-қувватлаш→ChatSupportScreen.
- NOT wired into shell: entertainment_catalog_tab.dart, jobs_complaints_tab.dart (embedded/sub-tabs).
- Badge streams (`_badgeCountStream`): orders status=='new', courier_orders pending, ads pending, dating_profiles pending, sell_submissions pending, driver_requests pending, birthdate_change_requests pending, pending_codes pending, trips marshrut pending, intercity_orders pending, risk_events reviewed==false, payout_requests pending, support_chats lastFromAdmin==false, NewsRepository.watchAdminUnreadCount.

## Auth / RBAC
- `admin_auth_service.dart`: trusted phone `998912778777` → CF adminWebSignIn (SMS-less custom token); others → Firebase Phone OTP; PIN → CF adminWebSignInWithCode. Role gate `_isAdminRole` ∈ {admin,superadmin,dispatcher}. Persists prefs user_role/phone/name.
- `admin_role_service.dart`: setUserRole → CF setUserRoleByAdmin.
- CF guard `requireCallerRoles`. Role sets: general admin {admin,superadmin,dispatcher}; finance ops {admin,superadmin,finance}; read-only ledger/audit {admin,superadmin,finance,auditor}. Vocabulary: user,admin,superadmin,dispatcher,finance,auditor,driver,courier.
- GOTCHA: embedded MonitoringCenterScreen skips client role re-check (trusts shell PIN session); security relies on login gate + CF requireCallerRoles.

## Screens (path under admin_web/screens → purpose)
admin_login(trusted/OTP/PIN) · admin_news_list(`admin_news` edit) · admin_order_news_list · admin_home_ticker(`home_ticker_ads`) · products_manager(`food_catalog`+images+extras) · procurement_prices(`procurement_products`) · taxi_price(`settings/prices` local) · warehouse_stock(read-only via CF) · sell_submissions_admin(`sell_submissions`) · payout_management(`payout_requests`, CF confirm/rejectPayout) · finance_center(Settlement Ledger, float, reconcile) · driver_applications(`driver_requests`) · marshrut_admin · marshrut_dispatch_history · intercity_admin · courier_admin · courier_management · courier_orders_admin · jobs_moderation(`ads`) · dating_moderation · identity_approvals(`birthdate_change_requests`) · birthday_bonus · pending_codes(`pending_codes`,`settings/app`) · users_devices(`device_bindings` SHA-256) · risk_review(`risk_events`) · anomaly_settings(`settings/anomaly_settings`) · chat_support(`support_chats`).

## Analytics (`features/analytics/`)
- ALL reads via `repositories/analytics_repository.dart` (collections users,drivers,orders,trips,schedules,driver_requests,payout_requests,daily_reports).
- `analytics_controller.dart`: lazy per-tab load (loadKpis/Users/Drivers/Operations/Finance/Reports, regenerateTodayReport via DailyReportService.forceRegenerate, refreshAll). Models in `models/analytics/` (KpiSummary,UserAnalytics,DriverAnalytics,OperationsAnalytics,FinanceAnalytics,DailyReport).
- `monitoring_center_screen.dart`: 5 tabs (Dashboard/Users/Drivers/Finance/Operations); `embedded` flag = shell mode. `daily_report_screen.dart` (today + 30-day). `admin_orders_screen.dart`, `admin_news_compose_screen.dart`.
- tabs dashboard_tab(KPI grid+LIVE banner)/operations_tab(heatmaps,trends,donuts)/users_tab/drivers_tab/finance_tab. widgets kpi_card/kpi_grid/trend_chart(fl_chart)/hourly_bar_chart/donut_chart/top_list/section_card.

## Gotchas
- Build: `flutter build web --release -t lib/main_admin.dart --base-href /admin/`; combined deploy `scripts/build_combined_web.ps1` → `firebase deploy --only hosting` (/=user, /admin/=admin).
- `dart:html` only in admin_shell.dart + same_origin_nav_web.dart + firestore_crash_guard_web.dart — never import into mobile build.
- Firestore web "Unexpected state" worked around by installFirestoreCrashGuard() + persistence disabled.
