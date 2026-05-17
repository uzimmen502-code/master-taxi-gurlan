import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// `master_taxi_driver` иловаси билан интеграция учун сервис.
///
/// Иккита асосий вазифа:
///   1. **Driver app ўрнатилганми?** — `canLaunchUrl(mastertaxidriver://)`
///      орқали аниқлaнади.
///   2. **Driver app'ни маълумотлар билан очиш** — `launchOnboard()` функцияси
///      `mastertaxidriver://onboard?phone=...&name=...&model=...&color=...&plate=...&taxiType=...`
///      URI'сини юборaди. Driver app шу маълумотларни ўз `RegisterScreen`'дa ёки
///      Firestore'дан auto-login'да ишлатaди.
///
///   3. **Driver app ўрнатилмаган бўлса** — `openApkDownload()` функцияси
///      браузерда APK файлини очaди (Firebase Hosting'дан).
class DriverAppLauncher {
  const DriverAppLauncher();

  /// Driver app'нинг deep link scheme'и (Android `<intent-filter>` мос).
  static const String _scheme = 'mastertaxidriver';
  static const String _host = 'onboard';

  /// Driver app APK файли — Firebase Hosting'да жойлашган.
  /// Production'да `web/downloads/master-taxi-gurlan-driver.apk`'га жўнатaди.
  static const String apkUrl =
      'https://master-taxi-gurlan.web.app/downloads/master-taxi-gurlan-driver.apk';

  /// Driver app телефонда ўрнатилганми текширади.
  /// Android'да `<queries>` манифестда керак (Android 11+ учун).
  Future<bool> isInstalled() async {
    try {
      // Бўш deep link билан текширамиз — фақат scheme'нинг мавжудлиги муҳим.
      final uri = Uri(scheme: _scheme, host: _host);
      return await canLaunchUrl(uri);
    } catch (_) {
      return false;
    }
  }

  /// Driver app'ни юклaб, фойдаланувчи маълумотлари билан onboarding'га
  /// йўналтиради. Driver app'нинг splash screen маълумотларни ўқиб:
  ///   - Агар `drivers/{uid}` Firestore'да мавжуд бўлса → auto-login → home
  ///   - Акс ҳолда → `RegisterScreen` pre-fill маълумотлари билан очилади
  ///
  /// `phone` — `+998xxxxxxxxx` ёки `998xxxxxxxxx` форматида тўлиқ телефон.
  /// `model`, `color`, `plate` — авто маълумотлари.
  /// `taxiType` — `'local'` (маҳаллий, default), `'marshrut'` ёки `'intercity'`.
  Future<bool> launchOnboard({
    required String phone,
    String name = '',
    String model = '',
    String color = '',
    String plate = '',
    String taxiType = 'local',
  }) async {
    final uri = Uri(
      scheme: _scheme,
      host: _host,
      queryParameters: {
        'phone': phone,
        if (name.isNotEmpty) 'name': name,
        if (model.isNotEmpty) 'model': model,
        if (color.isNotEmpty) 'color': color,
        if (plate.isNotEmpty) 'plate': plate,
        'taxiType': taxiType,
      },
    );
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Browser'дa APK юклаш саҳифасини очaди.
  /// Driver app ўрнатилмаган бўлгандa фойдаланилади.
  /// Браузер очилмаса (масалан, эмулятор), `Clipboard`'га ҳаволa қўйилaди ва
  /// `false` qaytarади.
  Future<bool> openApkDownload() async {
    final uri = Uri.parse(apkUrl);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return true;
    } catch (_) {
      // continue to clipboard fallback
    }
    try {
      await Clipboard.setData(const ClipboardData(text: apkUrl));
    } catch (_) {
      // ignore
    }
    return false;
  }
}
