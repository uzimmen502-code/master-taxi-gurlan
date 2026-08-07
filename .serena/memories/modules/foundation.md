# Foundation (home + onboarding + profile + core services)

Schema: `mem:firestore_schema`. CFs: `mem:cloud_functions`.

## home (`features/home/`)
- Entry `home_screen.dart` (re-exported by screens/home_screen.dart); home_controller.dart, home_grid_layout.dart, home_modules_catalog.dart (HomeModulesCatalog.modules: bread,food,sell,cheap_products_home,marshrut,local_taxi,intercity,jobs).
- widgets **home_global_search** (before featured; `search_index` + GlobalSearch), featured_products_section (title «Улгуржи…тавсия» → PlatformStoreScreen / AVA дўкони), product_feed_section, home_jobs_preview_section (after feed: max 8 compact ИШ ЭЪЛОН rows, urgent first, see-all→JobsScreen), promo_carousel, **services_spotlight_carousel** (1×4 snap; title «Хизматлар - танланг» → **AllServicesScreen** 3-col grid of same items; `_servicesCarouselEpoch` on Home return restarts). WalletCard auto-hides after 5s (`AnimatedSize` collapse); `_walletRevealEpoch` + `_onHomeResurface` shows again on Home return. Order: local, intercity, marshrut, yuk_birja, sell, food, jobs, market, bread, oil, circles, dating, courier, milk, tire, car_wash, carpet. wallet_card, home_info_ticker/home_ticker_bar, home_bottom_bar. Routes: orders,cheap_products,bread,food,courier hub,intercity,jobs,local_taxi,marshrut,sell,circles,wallet,profile, yuk_birja.
- Module id `yuk_birja` in `kKnownModuleIds`; icon `assets/images/services/service_yuk_birja.png`.

## yuk_birja (`features/yuk_birja/`) — dual scope 2026-08
- Shell tabs: **Туман ичида** (`local`) | **Шаҳарлараро** (`intercity`). Default = local.
- **Шаҳарлараро** = legacy `yuk_listings` MVP (unchanged): cargo|truck ads, TTL 48h, `createdAt` sort, call/edit/close/report. Lazy-loaded when tab opened.
- **Туман ичида** = live nearby trucks: collection `yuk_local_drivers/{phoneUid}` (GPS, acceptRadiusKm 5/10/15/20/50/citywide=999, plate, body L×W×H, loadStatus empty|busy|offline, rating, completedLoads, lastOnlineAt). Rank: readiness → in-radius → ETA → roadKm → rating. P0 road/ETA = haversine×1.35 / 27km/h (Directions later). Call + Chat.
- Files: `yuk_local_driver.dart`, `yuk_local_drivers_repository.dart`, `yuk_local_ranking.dart`, `yuk_accept_radius.dart`, `yuk_local_nearby_panel.dart`, `yuk_local_driver_sheet.dart`.
- Indexes: `online`+`lastOnlineAt` DESC. Rules: auth read; owner create/update (rating/completedLoads locked for clients).
- Also: vehicle types via l10n (`yuk_*`); IntercityPlaces filters on intercity tab; dark/yellow UI.

## onboarding (`features/onboarding/`)
- Flow 2026-08: **LanguageSelectScreen** = til + tuman (bitta ekran, viloyat/area yashirin; primary `serviceAreaId` avto). Prefs `pre_onboarding_*` + `ServiceConfigHolder.applyGeo` → **OnboardingScreen** (ism/telefon/jins/tug‘ilgan kun + `ob_phone_bind_warning`) → fingerprint login → Home. Zona/GPS/manzil/avto qadami olib tashlangan; ZoneGate + profil zonani saqlaydi.
- OnboardingController `totalPages=1`: identity (ism/telefon) → `checkDeviceBinding` → bootstrap/`createPhoneSession` → Home. Pending-code / admin OTP UI **olib tashlangan**. `loadPreselectedGeo()` pre-screen zonani oladi; GPS majburiy emas; `skipCarStep=true`.
- Phone auth (NOT Firebase SMS): DeviceFingerprintService → `checkDeviceBinding` (europe-west1) → **OnboardingBootstrapScreen** → `createPhoneSession` → prefs → Home; profile‖zone‖FCM фон. Warmup both CFs on til screen. **First bind / trusted:** fingerprint auto-link (`fingerprint_first_bind`) + session. Conflict (`device_bound_other_phone` / `phone_bound_other_device` / blocked) blocked unless `settings/app.deviceBindingAutoApprove`. `needs_verification` (rare first-bind fail) → error + retry, no code UI. PhoneReverify/AuthRestore: same fingerprint + `createPhoneSession`. CF `requestPendingCode`/`verifyPendingCodeAndRegister` may still exist server-side but client onboarding does not call them. **Auth claim:** `createPhoneCustomToken` + `setCustomUserClaims({phone_number})`; client `getIdToken(true)` after sign-in.
- finish(): force `getIdToken(true)` then `UserRepository.createOrMergeProfileWithAddress(..., requireCompleteAddress: false)` — MFY/street/house/GPS optional at signup (fill later in profile); merge `set`, **no** existence `get`; prefs + `saveServiceArea` from preselected geo, refresh FCM. Screens: onboarding/phone_reverify/auth_restore/language_select.

## profile (`features/profile/`)
- profile_controller.dart (wraps CF changeDevicePhone); screens profile/user_info/wallet/wallet_partner_program/wallet_operations_tab/address_edit/news_hub/news/*_news_detail/messages_tab; widgets wallet_section/wallet_ledger_list/**wallet_telegram_link_panel**/wallet_withdraw_panel/order_card/trip_card/language_settings_tile. Role via UserRoleSync. wallet uses wallet_ledger_entry model + `core/utils/wallet_ledger_labels.dart`. Telegram top-up: one-tap «Ҳамённи тўлдириш» → bot deposit → admin approve; withdraw: «Ҳамёндан пул ечиш» → `requestWalletWithdraw` → admin approve.

## Cold-start (`lib/main.dart`)
- Blocking before `runApp`: Firebase + Firestore settings, SharedPreferences routing flags, `ServiceConfigHolder.loadCacheOnly()`, `SplashTaglinesHolder.prepareSessionSync()`.
- Parallel unawaited: splash network `load()`, `PassengerCancelRulesHolder.load()`, daily report.
- `AppLaunchSplash` ~3.0s (900+1600+500ms); composition: top `BrandTitleColumn` (AVA+district), center logo spiral/pulse/exit, bottom rotating `SplashTaglinesHolder.sessionWords`. `onFinished` → `_deferredMobileBootstrap`: UserRoleSync, NotificationDelivery → NotificationService → FCM init/listeners → BackgroundGpsService.init. Home refreshes `ServiceConfigHolder.bootstrap()` post-frame.
- Brand hierarchy: display `AVA` + short district context (`BrandLabels` / `ServiceConfigHolder.districtLabel`); package/applicationId stay `ava_gurlan` / `uz.ava.gurlan`. Never `AVA Zona`.

## Core services (`lib/services/`)
- user_role_sync.dart UserRoleSync — server-authoritative role; `users/{uid}.role` vs prefs; privilegedRoles{admin,superadmin,dispatcher} Firestore wins; reconcile/forceSyncDriver; isClientAssignableRole{user,driver,courier}.
- background_gps_service.dart — foreground service, driver GPS every 20s → `drivers/{id}`; channel gps_channel; stops when pref driver_online=false.
- mfy_service.dart MfyService — static, loads assets/data/mfy_list.json; district→MFY lookup/search.
- device_fingerprint_service.dart — SHA-256 composite (androidId, firebaseInstallationId, model, brand, fingerprint...).
- balance_service.dart — CF creditChange, grantBirthdayBonus.
- settlement_service.dart — CF openSettlement/confirmSettlement/submitDeferredSettlement/cancelSettlement.
- deferred_settlement_queue.dart — offline-lite queue pref `deferred_settlements_v1`; dedupe by opId; flush→submitDeferredSettlement; maxAttempts=30.
- order_payment_service.dart — CF placeOrderPostPaid + courier* payment CFs.
- collection_service.dart — CF adminCreateCollectionTask/courierFinalizeCollection/adminGetWarehouseStock.
- courier_route_service.dart — CF courierCreateRoute/courierRecoverOrphanRoute; `delivery_routes`.
- marshrut_pricing_service.dart — CF seedMarshrutRoutePrice/adminSetMarshrutRoutePrice.
- driver_role_service.dart — CF leaveDriverRole/adminResetTaxiDriversRegistry.
- google_directions_service.dart — CF Directions proxy; polyline_decoder.dart decodes.
- fcm_service.dart — FCM token + background push; `notifications`. notification_delivery/notification_service/arrival_ringer/push_navigation.
- featured_products_service.dart — bread+food+platform_products (tap: bread/food modules, platform→PlatformStoreScreen; title «Тавсия этамиз»). product_feed_service — still bread/food/ads (market mix later). См. `mem:modules/platform_store`.
- Money display: `formatPrice` → `1 234 567`, `formatMoney` → `1 234 567 сўм` (`lib/core/utils/formatters.dart`, `kCurrencySum`). No commas / so'm / сум.
- Catalog search (`lib/core/utils/catalog_search.dart`): AND filter + ranking ladder exact→whole word→prefix→stem→compound→extra→weak; used by platform store, cheap products, ads search, jobs, oil ref, admin market/jobs moderation. Not for phone/ID/MFY/geo.
- daily_report_service.dart — 20:00 report (client + scheduled CF backup).
- location_service.dart, geo_math_service.dart, courier_delivery_route_optimizer.dart, intercity_pickup_route_service.dart (Directions optimize:true), admin_service.dart (client admin gate).
