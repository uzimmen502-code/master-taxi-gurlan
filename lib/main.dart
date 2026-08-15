// Web: фойдаланувчи иловаси. Бир хостда админ билан: `scripts/build_combined_web.ps1`
// → `/` бу entry, `/admin/` — `main_admin.dart` (firebase.json: public = build/hosting).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'repositories/analytics_repository.dart';
import 'repositories/bread_repository.dart';
import 'repositories/carpet_wash_orders_repository.dart';
import 'repositories/agro_pickup_orders_repository.dart';
import 'repositories/chat_repository.dart';
import 'repositories/collection_tasks_repository.dart';
import 'repositories/couriers_repository.dart';
import 'repositories/delivery_routes_repository.dart';
import 'repositories/driver_repository.dart';
import 'repositories/entertainment_repository.dart';
import 'repositories/intercity_bookings_repository.dart';
import 'repositories/intercity_rides_repository.dart';
import 'repositories/inventory_repository.dart';
import 'repositories/jobs_repository.dart';
import 'repositories/home_ticker_repository.dart';
import 'repositories/news_repository.dart';
import 'repositories/sell_offers_repository.dart';
import 'repositories/marshrut_driver_repository.dart';
import 'repositories/orders_repository.dart';
import 'repositories/queue_repository.dart';
import 'repositories/rides_repository.dart';
import 'repositories/schedules_repository.dart';
import 'repositories/settings_repository.dart';
import 'repositories/trips_repository.dart';
import 'repositories/user_repository.dart';
import 'services/admin_service.dart';
import 'services/user_role_sync.dart';
import 'services/daily_report_service.dart';
import 'services/fcm_service.dart';
import 'services/device_transfer_inbox_service.dart';
import 'services/background_gps_service.dart';
import 'services/location_service.dart';
import 'services/notification_delivery.dart';
import 'services/notification_service.dart';
import 'features/dating/services/dating_youth_promo_service.dart';
import 'core/navigation/app_route_observer.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_launch_splash.dart';
import 'core/widgets/zone_gate.dart';
import 'features/home/screens/home_screen.dart';
import 'core/utils/formatters.dart';
import 'features/onboarding/screens/auth_restore_screen.dart';
import 'features/onboarding/screens/language_select_screen.dart';
import 'features/onboarding/screens/onboarding_screen.dart';
import 'features/ads/repositories/ads_repository.dart';
import 'features/ads/services/ads_storage_service.dart';
import 'core/l10n/locale_notifier.dart';
import 'core/passenger_cancel_rules_holder.dart';
import 'core/splash_taglines_holder.dart';
import 'core/service_config_holder.dart';
import 'core/utils/firestore_crash_guard.dart';
import 'services/deferred_settlement_queue.dart';
import 'utils/locale_utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firestore veb SDK "Unexpected state" bug'idan avto-tiklash (faqat web).
  installFirestoreCrashGuard();

  // —— Stage A: birinchi frame uchun majburiy ——
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  final prefs = await SharedPreferences.getInstance();
  final languageSelected = prefs.containsKey('saved_language');
  final onboarding = prefs.getBool('onboarding_done') ?? false;
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final hasFirebaseAuth = firebaseUser != null;
  final storedPhone = phoneDigits(prefs.getString('user_phone') ?? '');
  final isReturningUser = onboarding || storedPhone.length >= 12;

  // Sessiya yo'qolsa (APK yangilash) — kod bilan qayta tasdiqlash kerak.
  if (isReturningUser && !hasFirebaseAuth) {
    await prefs.setBool('phone_reverified', false);
  }

  // Module gating — oxirgi kesh; Firestore refresh Home post-frame'da.
  await ServiceConfigHolder.loadCacheOnly();
  // Splash tagline'lar darhol ko'rinsin (default/pool).
  SplashTaglinesHolder.prepareSessionSync();

  // —— Stage B: splash/UI bilan parallel (Firestore network) ——
  unawaited(SplashTaglinesHolder.load());
  unawaited(PassengerCancelRulesHolder.load());

  final analyticsRepo = AnalyticsRepository();
  final reportService = DailyReportService(analyticsRepo);
  unawaited(reportService.ensureToday());

  final userId = prefs.getString('userId') ?? '';
  runApp(MyApp(
    isReturningUser: isReturningUser,
    languageSelected: languageSelected,
    hasFirebaseAuth: hasFirebaseAuth,
    userId: userId,
    analyticsRepo: analyticsRepo,
    reportService: reportService,
    deferRoleSync: onboarding,
  ));
}

/// Splash tugagach: FCM / GPS / notification / role sync.
Future<void> _deferredMobileBootstrap({required bool deferRoleSync}) async {
  if (deferRoleSync) {
    try {
      await UserRoleSync().syncToPreferences();
    } catch (e, st) {
      debugPrint('UserRoleSync (deferred): $e\n$st');
    }
  }

  if (kIsWeb) return;

  try {
    await NotificationDelivery.ensureInitialized();
  } catch (e, st) {
    debugPrint('NotificationDelivery (deferred): $e\n$st');
  }

  try {
    await NotificationService.instance.setup();
  } catch (e, st) {
    debugPrint('NotificationService.setup (deferred): $e\n$st');
  }

  // navigatorKey tayyor — cold-start push navigation ishlaydi.
  try {
    await FCMService().init();
    await FCMService().startListeners();
  } catch (e, st) {
    debugPrint('FCM init (deferred): $e\n$st');
  }

  unawaited(DeviceTransferInboxService.instance.checkOnce());

  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    try {
      await BackgroundGpsService.init();
    } catch (e, st) {
      debugPrint('BackgroundGpsService.init (deferred): $e\n$st');
    }
  }
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    required this.isReturningUser,
    required this.languageSelected,
    required this.hasFirebaseAuth,
    required this.userId,
    required this.analyticsRepo,
    required this.reportService,
    this.deferRoleSync = false,
  });

  final bool isReturningUser;
  final bool languageSelected;
  final bool hasFirebaseAuth;
  final String userId;
  final AnalyticsRepository analyticsRepo;
  final DailyReportService reportService;

  /// Onboarding tugagan bo'lsa — Firestore role sync splash'dan keyin.
  final bool deferRoleSync;

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _deferredBootstrapped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // FCM/notification/GPS — splash tugagach (ruxsat dialog splash ustida chiqmasin).
  }

  void _onSplashFinished() {
    if (_deferredBootstrapped) return;
    _deferredBootstrapped = true;
    unawaited(_deferredMobileBootstrap(
      deferRoleSync: widget.deferRoleSync,
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ServiceConfigHolder.bootstrap());
      unawaited(DeferredSettlementQueue.flush());
      unawaited(DatingYouthPromoService.maybeShowOnAppOpen());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => LocaleNotifier()..init(),
        ),
        Provider<UserRepository>(create: (_) => UserRepository()),
        Provider<OrdersRepository>(create: (_) => OrdersRepository()),
        Provider<InventoryRepository>(create: (_) => InventoryRepository()),
        Provider<NewsRepository>(create: (_) => NewsRepository()),
        Provider<HomeTickerRepository>(create: (_) => HomeTickerRepository()),
        Provider<SellOffersRepository>(create: (_) => SellOffersRepository()),
        Provider<BreadRepository>(create: (_) => BreadRepository()),
        Provider<CarpetWashOrdersRepository>(
            create: (_) => CarpetWashOrdersRepository()),
        Provider<AgroPickupOrdersRepository>(
            create: (_) => AgroPickupOrdersRepository()),
        Provider<JobsRepository>(create: (_) => JobsRepository()),
        Provider<TripsRepository>(create: (_) => TripsRepository()),
        Provider<DriverRepository>(create: (_) => DriverRepository()),
        Provider<ChatRepository>(create: (_) => ChatRepository()),
        Provider<RidesRepository>(create: (_) => RidesRepository()),
        Provider<SchedulesRepository>(create: (_) => SchedulesRepository()),
        Provider<QueueRepository>(create: (_) => QueueRepository()),
        Provider<MarshrutDriverRepository>(
            create: (_) => MarshrutDriverRepository()),
        Provider<IntercityRidesRepository>(
            create: (_) => IntercityRidesRepository()),
        Provider<IntercityBookingsRepository>(
            create: (_) => IntercityBookingsRepository()),
        Provider<EntertainmentRepository>(
            create: (_) => EntertainmentRepository()),
        Provider<DeliveryRoutesRepository>(
            create: (_) => DeliveryRoutesRepository()),
        Provider<CollectionTasksRepository>(
            create: (_) => CollectionTasksRepository()),
        Provider<CouriersRepository>(create: (_) => CouriersRepository()),
        Provider<SettingsRepository>(create: (_) => SettingsRepository()),
        Provider<AdsStorageService>(create: (_) => AdsStorageService()),
        Provider<AdsRepository>(create: (_) => AdsRepository()),
        Provider<AnalyticsRepository>.value(value: widget.analyticsRepo),
        Provider<DailyReportService>.value(value: widget.reportService),
        Provider<LocationService>(create: (_) => const LocationService()),
        Provider<AdminService>(create: (_) => AdminService()),
      ],
      child: Consumer<LocaleNotifier>(
        builder: (context, localeNotifier, _) {
          return AppLaunchSplash(
            onFinished: _onSplashFinished,
            child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            locale: localeNotifier.locale,
            supportedLocales: LocaleUtils.supportedAppLocales,
            localeResolutionCallback: LocaleUtils.localeResolutionCallback,
            navigatorKey: MyApp.navigatorKey,
            navigatorObservers: [appRouteObserver],
            debugShowCheckedModeBanner: false,
            title: 'AVA',
            theme: AppTheme.light,
            home: !widget.languageSelected
                ? const LanguageSelectScreen()
                : !widget.isReturningUser
                    ? const OnboardingScreen()
                    : widget.hasFirebaseAuth
                        ? const ZoneGate(child: HomeScreen())
                        : const AuthRestoreScreen(),
            ),
          );
        },
      ),
    );
  }
}
