import 'package:shared_preferences/shared_preferences.dart';

/// Web (QR орқали кирилган браузер): сессия ID + renewSecret. renewSecret — шу браузернинг
/// «боғланиш»и (телефондаги device binding ўрнида): Firebase refresh token бекор қилинганда
/// (`qrWebSessionRenew`) жим қайта кириш учун. Телефондан «Чиқиш» → сервер уни рад этади.
///
/// Чиқишда `LocaleUtils.clearPrefsKeepingLanguage` бутун prefs'ни тозалайди — шу калитлар ҳам.
class QrWebSession {
  const QrWebSession({
    required this.webSessionId,
    required this.renewSecret,
    required this.phone,
    this.expiresAtMs = 0,
  });
  final String webSessionId;
  final String renewSecret;
  final String phone;
  final int expiresAtMs;

  bool expiredAt(int nowMs) => expiresAtMs > 0 && expiresAtMs <= nowMs;
}

class QrWebSessionStore {
  static const kId = 'qr_ws_id';
  static const kSecret = 'qr_ws_secret';
  static const kPhone = 'qr_ws_phone';
  static const kExp = 'qr_ws_exp';

  static Future<QrWebSession?> load() async {
    final p = await SharedPreferences.getInstance();
    final id = p.getString(kId) ?? '';
    final secret = p.getString(kSecret) ?? '';
    if (id.isEmpty || secret.isEmpty) return null;
    return QrWebSession(
      webSessionId: id,
      renewSecret: secret,
      phone: p.getString(kPhone) ?? '',
      expiresAtMs: p.getInt(kExp) ?? 0,
    );
  }

  static Future<void> save(QrWebSession s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(kId, s.webSessionId);
    await p.setString(kSecret, s.renewSecret);
    await p.setString(kPhone, s.phone);
    await p.setInt(kExp, s.expiresAtMs);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    for (final k in const [kId, kSecret, kPhone, kExp]) {
      await p.remove(k);
    }
  }
}
