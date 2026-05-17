import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart' as fmt;

/// Web админ панели учун аутентификaция сервиси.
///
/// 2 қадaмли логин:
///   1. **Phone** — Firestore'дa `users/{uid}` ҳужжати мaвжуд бўлсин ва
///      `role == 'admin'` бўлсин.
///   2. **PIN** — Мобил иловaдaги бирхил PIN (`user_info_screen.dart`'дa
///      `_adminPinCode`).
///
/// **Хавфсизлик**: Phone Auth ишлaтилмaгaни сабaб, шу йўл client-side қулф —
/// Кейинги Phase'дa Firebase Auth Custom Token билaн ўрнини алмaштирaмиз.
///
/// Sессия SharedPreferences'дa (web'дa cookie/localStorage'да автомaтик
/// сaқлaнaди).
class AdminAuthService extends ChangeNotifier {
  AdminAuthService({
    FirebaseFirestore? db,
    required String adminPinCode,
  })  : _db = db ?? FirebaseFirestore.instance,
        _adminPinCode = adminPinCode;

  final FirebaseFirestore _db;
  final String _adminPinCode;

  static const _kPhoneKey = 'admin_web_phone';
  static const _kSessionKey = 'admin_web_session';
  static const _sessionTtl = Duration(hours: 12);

  String? _phone;
  String? _phoneDigits;
  String? _displayName;
  DateTime? _sessionStart;

  bool get isLoggedIn => _phoneDigits != null && _sessionStart != null;
  String? get phone => _phone;
  String? get phoneDigits => _phoneDigits;
  String? get displayName => _displayName;

  /// App startup'да чaқирилaди — кэшлaнгaн сессияни qайтарaди.
  Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedPhone = prefs.getString(_kPhoneKey);
    final sessionStartMs = prefs.getInt(_kSessionKey);
    if (cachedPhone == null || sessionStartMs == null) return;
    final started = DateTime.fromMillisecondsSinceEpoch(sessionStartMs);
    if (DateTime.now().difference(started) > _sessionTtl) {
      await logout();
      return;
    }
    final digits = fmt.phoneDigits(cachedPhone);
    if (digits.length < 9) return;
    // Firestore'да role'ни tekshirish — admin emas bo'lsa session bekor.
    try {
      final snap = await _db.collection('users').doc(digits).get();
      final role = snap.data()?['role'] as String? ?? '';
      if (role != 'admin' && role != 'superadmin') {
        await logout();
        return;
      }
      _phone = cachedPhone;
      _phoneDigits = digits;
      _displayName = (snap.data()?['name'] as String?) ?? '';
      _sessionStart = started;
      // Web restart'дaн кейин SharedPrefs прaйминг.
      await prefs.setString('user_phone', cachedPhone);
      await prefs.setString('user_role', 'admin');
      await prefs.setString('user_name', _displayName ?? '');
      notifyListeners();
    } catch (_) {
      await logout();
    }
  }

  /// Phone + PIN бўйича логин.
  ///
  /// Қайтараётганлар:
  ///   - `null` — мувaффaқиятли
  ///   - `String` — xато xабaри
  Future<String?> signIn({
    required String rawPhone,
    required String pin,
  }) async {
    final digits = fmt.phoneDigits(rawPhone);
    if (digits.length < 9) {
      return 'Телефон рaқaми ноtўғри (минимум 9 рaқaм).';
    }
    if (pin != _adminPinCode) {
      return 'PIN-код xато.';
    }
    try {
      final snap = await _db.collection('users').doc(digits).get();
      if (!snap.exists) {
        return 'Бу телефон Firestore\'дa қайд эtилмaгaн. Аввал илoвaдa '
            'рўйхaтдан ўтинг.';
      }
      final role = snap.data()?['role'] as String? ?? '';
      if (role != 'admin' && role != 'superadmin') {
        return 'Сиз Админ эмaсcиз. Mobil ilovada: Profil → '
            '«🔒 Админ ролини faollashtirish» (PIN 2024) yoki Firebase Console\'da '
            'users/$digits → role = admin.';
      }
      _phone = rawPhone;
      _phoneDigits = digits;
      _displayName = (snap.data()?['name'] as String?) ?? '';
      _sessionStart = DateTime.now();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPhoneKey, rawPhone);
      await prefs.setInt(_kSessionKey, _sessionStart!.millisecondsSinceEpoch);

      // ⚠️ МУҲИМ: Дounstream компонентлaр (`AdminService`,
      // `MonitoringCenterScreen`, `AnalyticsController`...) SharedPreferences'дaги
      // `user_phone` ва `user_role`-ни текширaди. Web'дa они сaқлaмaсaк, барча
      // admin checks rad etilади. Шу сaбaб бу ердa ҳaм set qилaмиз.
      await prefs.setString('user_phone', rawPhone);
      await prefs.setString('user_role', 'admin');
      await prefs.setString('user_name', _displayName ?? '');
      notifyListeners();
      return null;
    } catch (e) {
      return 'Firestore xатoси: $e';
    }
  }

  Future<void> logout() async {
    _phone = null;
    _phoneDigits = null;
    _displayName = null;
    _sessionStart = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPhoneKey);
    await prefs.remove(_kSessionKey);
    // Downstream admin checks учун qўйилгaн кaлитлaрни ҳaм тoзaлaймиз.
    await prefs.remove('user_phone');
    await prefs.remove('user_role');
    await prefs.remove('user_name');
    notifyListeners();
  }
}
