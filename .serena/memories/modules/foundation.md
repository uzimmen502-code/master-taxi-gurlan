# Foundation (home + onboarding + profile + core services)

Schema: `mem:firestore_schema`. CFs: `mem:cloud_functions`.

## home (`features/home/`)
- Entry `home_screen.dart` (re-exported by screens/home_screen.dart); home_controller.dart, home_grid_layout.dart, home_modules_catalog.dart (HomeModulesCatalog.modules: bread,food,sell,cheap_products_home,marshrut,local_taxi,intercity,jobs).
- widgets featured_products_section, product_feed_section, promo_carousel, wallet_card, home_info_ticker/home_ticker_bar, home_header, home_bottom_bar. Reads IntercityBookingsRepository,UserRepository,HomeTickerRepository; routes to feature screens (orders,cheap_products,bread,food,courier hub,intercity,jobs,local_taxi,marshrut,sell,circles,wallet,profile).

## onboarding (`features/onboarding/`)
- onboarding_controller.dart (7 pages name→phone→OTP→...→address→optional car+bonus); screens onboarding/phone_reverify/auth_restore/language_select.
- Phone auth = ADMIN-CODE flow (NOT Firebase SMS): DeviceFingerprintService → checkDeviceBinding (CF) → trustedDevice signInWithCustomToken; else requestPendingCode (CF) → watch PendingCodeRepository → verifyPendingCodeAndRegister (CF) → customToken sign-in.
- finish(): UserRepository.createOrMergeProfileWithAddress, prefs (user_phone/name/role via canonicalPhoneId, onboarding_done, phone_reverified), refresh FCM. District default Гурлан/Gurlan; MfyService autocomplete.

## profile (`features/profile/`)
- profile_controller.dart (wraps CF changeDevicePhone); screens profile/user_info/wallet/wallet_partner_program/wallet_operations_tab/address_edit/news_hub/news/*_news_detail/messages_tab; widgets wallet_section/wallet_ledger_list/order_card/trip_card/language_settings_tile. Role via UserRoleSync. wallet uses wallet_ledger_entry model + `core/utils/wallet_ledger_labels.dart`.

## Cold-start (`lib/main.dart`)
- Blocking before `runApp`: Firebase + Firestore settings, SharedPreferences routing flags, `ServiceConfigHolder.loadCacheOnly()`, `SplashTaglinesHolder.prepareSessionSync()`.
- Parallel unawaited: splash network `load()`, `PassengerCancelRulesHolder.load()`, daily report.
- Post-frame deferred (`_deferredMobileBootstrap`): UserRoleSync, NotificationDelivery → NotificationService → FCM init/listeners → BackgroundGpsService.init. Home still refreshes `ServiceConfigHolder.bootstrap()` post-frame.

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
- featured_products_service.dart / product_feed_service.dart — feeds from bread_products,food_catalog,ads(cheap_product active).
- daily_report_service.dart — 20:00 report (client + scheduled CF backup).
- location_service.dart, geo_math_service.dart, courier_delivery_route_optimizer.dart, intercity_pickup_route_service.dart (Directions optimize:true), admin_service.dart (client admin gate).
