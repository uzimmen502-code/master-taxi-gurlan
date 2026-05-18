// Web: фойдаланувчи иловаси. Бир хостда админ билан: `scripts/build_combined_web.ps1`
// → `/` бу entry, `/admin/` — `main_admin.dart` (firebase.json: public = build/hosting).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'repositories/analytics_repository.dart';
import 'repositories/bread_repository.dart';
import 'repositories/chat_repository.dart';
import 'repositories/couriers_repository.dart';
import 'repositories/delivery_routes_repository.dart';
import 'repositories/driver_repository.dart';
import 'repositories/intercity_bookings_repository.dart';
import 'repositories/intercity_rides_repository.dart';
import 'repositories/inventory_repository.dart';
import 'repositories/jobs_repository.dart';
import 'repositories/news_repository.dart';
import 'repositories/marshrut_driver_repository.dart';
import 'repositories/orders_repository.dart';
import 'repositories/queue_repository.dart';
import 'repositories/rides_repository.dart';
import 'repositories/schedules_repository.dart';
import 'repositories/trips_repository.dart';
import 'repositories/user_repository.dart';
import 'services/admin_service.dart';
import 'services/daily_report_service.dart';
import 'services/fcm_service.dart';
import 'services/background_gps_service.dart';
import 'services/location_service.dart';
import 'services/notification_service.dart';
import 'features/home/screens/home_screen.dart';
import 'features/onboarding/screens/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Web'da notification permission / messaging init ayrim браузерларда
  // birinchi frame'dan oldin osilib qolishi мумкин. UI аввал чиқсин.
  if (!kIsWeb) {
    try {
      await FCMService().init();
      await FCMService().startListeners(); // Firestore listeners
    } catch (e, st) {
      debugPrint('FCM init: $e\n$st');
    }
  }

  // flutter_background_service фақат Android/iOS (веб/Windowsда configure хато).
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    try {
      await BackgroundGpsService.init();
    } catch (e, st) {
      debugPrint('BackgroundGpsService.init: $e\n$st');
    }
  }

  if (!kIsWeb) {
    try {
      await NotificationService.instance.setup();
    } catch (e, st) {
      debugPrint('NotificationService.setup: $e\n$st');
    }
  }

  // Кундалик ҳисобот xizmati: 20:00 фdа лoкал генерация
  // (Cloud Function ҳам худди шу вақтда серверда ишлайди).
  final analyticsRepo = AnalyticsRepository();
  final reportService = DailyReportService(analyticsRepo);
  unawaited(reportService.ensureToday());

  final prefs = await SharedPreferences.getInstance();
  final onboarding = prefs.getBool('onboarding_done') ?? false;

  final userId = prefs.getString('userId') ?? '';
  runApp(MyApp(
    onboardingDone: onboarding,
    userId: userId,
    analyticsRepo: analyticsRepo,
    reportService: reportService,
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.onboardingDone,
    required this.userId,
    required this.analyticsRepo,
    required this.reportService,
  });

  final bool onboardingDone;
  final String userId;
  final AnalyticsRepository analyticsRepo;
  final DailyReportService reportService;

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<UserRepository>(create: (_) => UserRepository()),
        Provider<OrdersRepository>(create: (_) => OrdersRepository()),
        Provider<InventoryRepository>(create: (_) => InventoryRepository()),
        Provider<NewsRepository>(create: (_) => NewsRepository()),
        Provider<BreadRepository>(create: (_) => BreadRepository()),
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
        Provider<DeliveryRoutesRepository>(
            create: (_) => DeliveryRoutesRepository()),
        Provider<CouriersRepository>(create: (_) => CouriersRepository()),
        Provider<AnalyticsRepository>.value(value: analyticsRepo),
        Provider<DailyReportService>.value(value: reportService),
        Provider<LocationService>(create: (_) => const LocationService()),
        Provider<AdminService>(create: (_) => AdminService()),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en'),
          Locale('ru'),
          Locale('uz'),
        ],
        navigatorKey: MyApp.navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'Master Taxi',
        home: onboardingDone ? const HomeScreen() : const OnboardingScreen(),
      ),
    );
  }
}
