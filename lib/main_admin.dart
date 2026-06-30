// ═════════════════════════════════════════════════════════════════════════
// MASTER TAXI GURLAN — АДМИН WEB ПАНЕЛИ ENTRY POINT
//
// Бу файл — Flutter Web учун alohida entry. Мобил `main.dart` ҳaмма мобил
// фeатурaлaрни (тaкси, курьер, нон ва ҳ.к.) ёқaди. Бу ерда фaқaт админ
// панели юклaнaди — кам пaкeт, тeз юклaш.
//
// Run/build (faqat admin):
//   flutter run -d chrome -t lib/main_admin.dart --base-href /admin/
//   flutter build web --release -t lib/main_admin.dart --base-href /admin/
//
// Локалда `/` да ochиш админни қайта юклайди — `--base-href /admin/` тавсия.
// Алоҳида user порти булса: `--dart-define=USER_DEV_URL=http://localhost:PORT/`
//
// Бир сайтда фойдаланувчи + админ (тавсия):
//   powershell -ExecutionPolicy Bypass -File scripts/build_combined_web.ps1
//   firebase deploy --only hosting
//   — / фойдаланувчи, /admin/ админ (firebase.json → public: build/hosting).
// ═════════════════════════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'features/admin_web/screens/admin_login_screen.dart';
import 'features/admin_web/screens/admin_shell.dart';
import 'features/admin_web/services/admin_auth_service.dart';
import 'features/admin_web/services/admin_news_read_service.dart';
import 'firebase_options.dart';
import 'repositories/analytics_repository.dart';
import 'repositories/bread_repository.dart';
import 'repositories/chat_repository.dart';
import 'repositories/delivery_routes_repository.dart';
import 'repositories/driver_repository.dart';
import 'repositories/inventory_repository.dart';
import 'repositories/jobs_repository.dart';
import 'repositories/home_ticker_repository.dart';
import 'repositories/news_repository.dart';
import 'repositories/sell_offers_repository.dart';
import 'repositories/orders_repository.dart';
import 'repositories/queue_repository.dart';
import 'repositories/rides_repository.dart';
import 'repositories/user_repository.dart';
import 'core/passenger_cancel_rules_holder.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/firestore_crash_guard.dart';
import 'services/admin_service.dart';
import 'services/daily_report_service.dart';
import 'services/procurement_prices_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firestore veb SDK "Unexpected state" bug'idan avto-tiklash (faqat web).
  installFirestoreCrashGuard();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );

  await PassengerCancelRulesHolder.load();

  // Аналитика репозиторий — daily report сервиси билaн боғлик.
  final analyticsRepo = AnalyticsRepository();
  final reportService = DailyReportService(analyticsRepo);

  // Auth — кэшлaнгaн сессияни тиклaйди.
  final auth = AdminAuthService();
  await auth.restoreSession();

  final adminNewsRead = AdminNewsReadService();
  await adminNewsRead.init();

  runApp(AdminWebApp(
    auth: auth,
    analyticsRepo: analyticsRepo,
    reportService: reportService,
    adminNewsRead: adminNewsRead,
  ));
}

class AdminWebApp extends StatelessWidget {
  const AdminWebApp({
    super.key,
    required this.auth,
    required this.analyticsRepo,
    required this.reportService,
    required this.adminNewsRead,
  });

  final AdminAuthService auth;
  final AnalyticsRepository analyticsRepo;
  final DailyReportService reportService;
  final AdminNewsReadService adminNewsRead;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AdminAuthService>.value(value: auth),
        ChangeNotifierProvider<AdminNewsReadService>.value(
            value: adminNewsRead),
        Provider<AnalyticsRepository>.value(value: analyticsRepo),
        Provider<DailyReportService>.value(value: reportService),
        Provider<NewsRepository>(create: (_) => NewsRepository()),
        Provider<HomeTickerRepository>(create: (_) => HomeTickerRepository()),
        Provider<SellOffersRepository>(create: (_) => SellOffersRepository()),
        Provider<UserRepository>(create: (_) => UserRepository()),
        Provider<BreadRepository>(create: (_) => BreadRepository()),
        Provider<InventoryRepository>(create: (_) => InventoryRepository()),
        Provider<JobsRepository>(create: (_) => JobsRepository()),
        Provider<DriverRepository>(create: (_) => DriverRepository()),
        Provider<OrdersRepository>(create: (_) => OrdersRepository()),
        Provider<QueueRepository>(create: (_) => QueueRepository()),
        Provider<RidesRepository>(create: (_) => RidesRepository()),
        Provider<DeliveryRoutesRepository>(
            create: (_) => DeliveryRoutesRepository()),
        Provider<ChatRepository>(create: (_) => ChatRepository()),
        Provider<AdminService>(create: (_) => AdminService()),
        Provider<ProcurementPricesService>(
          create: (_) => ProcurementPricesService(),
        ),
      ],
      child: MaterialApp(
        title: 'AVA Gurlan — Admin',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.adminWeb,
        home: const _AuthGate(),
      ),
    );
  }
}

/// Auth ҳолатини текширaди — логин ёки asосий экран.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AdminAuthService>();
    if (auth.isLoggedIn) {
      return const AdminShell();
    }
    return const AdminLoginScreen();
  }
}
