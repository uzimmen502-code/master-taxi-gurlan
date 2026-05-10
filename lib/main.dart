import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'services/fcm_service.dart';
import 'services/background_gps_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';
import 'screens/local_taxi_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Offline cache yoqish
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  await FCMService().init();
  await FCMService().startListeners(); // Firestore listeners
  await BackgroundGpsService.init();

  final prefs        = await SharedPreferences.getInstance();
  final onboarding   = prefs.getBool('onboarding_done') ?? false;


  final userId = prefs.getString('userId') ?? '';
  runApp(MyApp(onboardingDone: onboarding, userId: userId));
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.onboardingDone,
    required this.userId,
  });

  final bool onboardingDone;
  final String userId;

  static final GlobalKey<NavigatorState> navigatorKey =
  GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
        home: onboardingDone ? const HomeScreen() : const OnboardingScreen()
    );
  }
}