import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Бош экран controller'и — фойдаланувчи, интернет, бир марталик agro promo.
class HomeController extends ChangeNotifier {
  HomeController() {
    _init();
  }

  String name = 'Фойдаланувчи';
  String gender = 'male';
  /// SharedPreferences `user_role` — UI учун (асл рuxсат Firestore / rules).
  String role = 'user';
  bool hasInternet = true;

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _disposed = false;

  /// Биринчи 3 кун ичида (биринчи ўрнатиш кунидан) бир марталик
  /// агро-промо диалогини кўрсатиш сигнали. UI подпиёса бўлади.
  final _agroPromoController = StreamController<String>.broadcast();
  Stream<String> get onAgroPromo => _agroPromoController.stream;

  Future<void> _init() async {
    await _loadUser();
    await _initConnectivity();
    await _maybeFireAgroPromo();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    name = prefs.getString('user_name') ?? 'Фойдаланувчи';
    gender = prefs.getString('user_gender') ?? 'male';
    role = prefs.getString('user_role') ?? 'user';
    if (!_disposed) notifyListeners();
  }

  /// Бош саҳифада «Админ панели» — `ProfileScreen` билан бир xил мантик.
  bool get isAdminOrSuperadmin =>
      role == 'admin' || role == 'superadmin';

  /// Профил экранидан қайтгандан кейин — балки исм ўзгарган.
  Future<void> refreshUser() => _loadUser();

  Future<void> _initConnectivity() async {
    final initial = await Connectivity().checkConnectivity();
    _updateConnectivity(initial);
    _connSub = Connectivity().onConnectivityChanged.listen(_updateConnectivity);
  }

  void _updateConnectivity(List<ConnectivityResult> results) {
    hasInternet = results.any((r) => r != ConnectivityResult.none);
    if (!_disposed) notifyListeners();
  }

  /// Биринчи ўрнатишдан 3 кун ичида, кунига бир марта.
  Future<void> _maybeFireAgroPromo() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final installMs =
        prefs.getInt('first_install_ms') ?? now.millisecondsSinceEpoch;
    await prefs.setInt('first_install_ms', installMs);
    final first = DateTime.fromMillisecondsSinceEpoch(installMs);
    final dayDiff =
        now.difference(DateTime(first.year, first.month, first.day)).inDays;
    if (dayDiff < 0 || dayDiff > 2) return;

    final key = '${now.year}-${now.month}-${now.day}';
    final sentKey = prefs.getString('promo_daily_key') ?? '';
    if (sentKey == key) return;
    await prefs.setString('promo_daily_key', key);

    final extra = Random().nextDouble() < 0.55
        ? '\n\n🎯 Таклиф: гўшт ўрнига сут, гуруч, тухум ва бошқа қишлоқ хўжалик маҳсулотлари билан ҳисоб-китоб қилиш имкони бор.'
        : '';
    final message =
        'Бизда Сут, Қатиқ, Тухум, Гуруч ва бошқа маҳсулотлар билан ҳам ҳисоб-китоб қилиш мумкин.$extra';
    _agroPromoController.add(message);
  }

  /// Соатга қараб салом.
  String greeting({
    String night = 'Яхши тун',
    String morning = 'Хайрли тонг',
    String day = 'Хайрли кун',
    String evening = 'Хайрли оқшом',
  }) {
    final h = DateTime.now().hour;
    if (h < 6) return night;
    if (h < 12) return morning;
    if (h < 17) return day;
    if (h < 21) return evening;
    return night;
  }

  /// Жинсга кўра мурожаат.
  String honorificName() {
    if (gender == 'female') return 'Опажон $name';
    return 'Биродарим $name';
  }

  @override
  void dispose() {
    _disposed = true;
    _connSub?.cancel();
    _agroPromoController.close();
    super.dispose();
  }
}
