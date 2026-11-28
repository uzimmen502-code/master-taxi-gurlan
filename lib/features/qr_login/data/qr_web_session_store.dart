import 'package:shared_preferences/shared_preferences.dart';

/// Web (QR орқали кирилган вкладка): сессия ID ва белги.
///
/// Эга 2026-11-28: доимий web кириш ЙЎҚ — «ҳар сафар кирганда янгидан сканерлаш», браузер ёпилса /
/// компьютер ўчиб-ёнса — тизимдан ажралади. Firebase Auth SESSION persistence (вкладка ёпилса token
/// йўқолади); жим қайта кириш сири сақланмайди. [kFlag] — кейинги очилишда (auth йўқ) QR кириш
/// изларини (телефон, исм) prefs'дан тозалаш учун.
class QrWebSession {
  const QrWebSession({
    required this.webSessionId,
    required this.phone,
    this.heartbeatIntervalMs = 5 * 60 * 1000,
  });
  final String webSessionId;
  final String phone;
  final int heartbeatIntervalMs;
}

class QrWebSessionStore {
  static const kId = 'qr_ws_id';
  static const kPhone = 'qr_ws_phone';
  static const kHeartbeat = 'qr_ws_hb_ms';

  /// Шу браузерда QR орқали кирилган (prefs'даги ҳисоб излари QR'дан).
  static const kFlag = 'qr_web_login';

  static Future<QrWebSession?> load() async {
    final p = await SharedPreferences.getInstance();
    final id = p.getString(kId) ?? '';
    if (id.isEmpty) return null;
    return QrWebSession(
      webSessionId: id,
      phone: p.getString(kPhone) ?? '',
      heartbeatIntervalMs: p.getInt(kHeartbeat) ?? 5 * 60 * 1000,
    );
  }

  static Future<void> save(QrWebSession s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(kId, s.webSessionId);
    await p.setString(kPhone, s.phone);
    await p.setInt(kHeartbeat, s.heartbeatIntervalMs);
    await p.setBool(kFlag, true);
  }

  static Future<bool> wasQrLogin() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(kFlag) ?? false;
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    for (final k in const [kId, kPhone, kHeartbeat, kFlag]) {
      await p.remove(k);
    }
  }
}
