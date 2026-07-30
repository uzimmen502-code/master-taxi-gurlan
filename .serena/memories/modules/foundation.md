# Foundation (home + onboarding + profile + core services)

Schema: `mem:firestore_schema`. CFs: `mem:cloud_functions`.

## home (`features/home/`)
- Entry `home_screen.dart` (re-exported by screens/home_screen.dart); home_controller.dart, home_grid_layout.dart, home_modules_catalog.dart (HomeModulesCatalog.modules: bread,food,sell,cheap_products_home,marshrut,local_taxi,intercity,jobs).
- widgets featured_products_section, product_feed_section, promo_carousel, wallet_card, home_info_ticker/home_ticker_bar, home_bottom_bar. Reads IntercityBookingsRepository,UserRepository,HomeTickerRepository; routes to feature screens (orders,cheap_products,bread,food,courier hub,intercity,jobs,local_taxi,marshrut,sell,circles,wallet,profile, **yuk_birja**).
- `_UnifiedServicesGrid`: 4×3 per page. **1-page**: local, intercity, marshrut, **yuk_birja** (was courier), sell, food, jobs, market, bread, oil, circles, dating. **2-page**: **courier**, milk, tire, car_wash, carpet.
- Module id `yuk_birja` in `kKnownModuleIds`; icon `assets/images/services/service_yuk_birja.png`.

## yuk_birja (`features/yuk_birja/`) — shared Firestore 2026-07
- UI + vehicle types via AppLocalizations (`yuk_*`, `yuk_vehicle_*`); latin vehicle codes + Cyrillic legacy map.
- Firestore `yuk_listings`; `YukListingsRepository.watchActive(limit: 10000)`; store waits first snapshot then screen runs `closeExpired` + `YukListingNotifier.syncOwner`. Owner id = `canonicalPhoneId`; ownership via `phonesMatch`.
- TTL 48h; CF `expirePendingTrips` closes expired + `notifications` (`yuk_listing_closed`); T−6h → `yuk_listing_expire_soon` once (`expireSoonNotified`). Local schedule still in `YukListingNotifier`.
- Report → `reports` type `yuk_listing`; load error banner + retry; search-on-submit; tools collapse; IntercityPlaces.
- Dark/yellow UI; HTML proto `docs/yuk_birjasi_prototype.html`.

## onboarding (`features/onboarding/`)
- onboarding_controller.dart (3 soft pages: identity+birth → admin OTP → zone/GPS + optional address/car); LanguageSelectScreen soft pills; finish allows empty MFY/street/house; screens onboarding/phone_reverify/auth_restore/language_select.
- Zone: viloyat hidden (Хоразм auto). GPS card: `ob_gps_required` = «GPS мажбурий» (Latin GPS); no lat/lng row — get/update button only.
- Address intelligence: street/house unlock when MFY non-empty (list pick OR free type); pick/submit → expand + street focus + ensureVisible; street submit → house focus. Identity subtitle «битта экранда» removed.
- Phone auth = ADMIN-CODE flow (NOT Firebase SMS): DeviceFingerprintService → checkDeviceBinding (CF) → trustedDevice signInWithCustomToken; else requestPendingCode (CF) → watch PendingCodeRepository → verifyPendingCodeAndRegister (CF) → customToken sign-in. **Auth claim:** `createPhoneCustomToken` persists `phone_number` via `setCustomUserClaims` (same as admin web); client always `getIdToken(true)` after custom-token sign-in so Firestore `isOwner()` sees the claim.
- finish(): force `getIdToken(true)` then `UserRepository.createOrMergeProfileWithAddress` (merge `set`, **no** existence `get` — read needs `isOwner`), prefs (user_phone/name via canonicalPhoneId, onboarding_done, phone_reverified), optional `saveServiceArea`+car, refresh FCM. District default Гурлан/Gurlan; MfyService autocomplete.

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
