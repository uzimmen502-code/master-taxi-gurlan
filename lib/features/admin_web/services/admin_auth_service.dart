import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/formatters.dart' as fmt;

/// Admin web auth: panel roli bor telefon — SMSsiz/parolsiz
/// (`adminWebSignIn` custom token). Maxfiy PIN — `adminWebSignInWithCode`.
class AdminAuthService extends ChangeNotifier {
  AdminAuthService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const _kPhoneKey = 'admin_web_phone';

  /// Legacy operator raqami (PIN orqali ham shu hisobga kiradi).
  static const String trustedAdminPhoneDigits = '998912778777';

  String? _phone;
  String? _phoneDigits;
  String? _displayName;
  String? _role;

  bool isSendingOtp = false;
  bool isVerifyingOtp = false;
  String? otpError;

  bool get isLoggedIn => _phoneDigits != null && _phoneDigits!.isNotEmpty;

  static bool isTrustedAdminPhone(String rawPhone) =>
      fmt.phoneDigits(rawPhone) == trustedAdminPhoneDigits;

  String? get phone => _phone;
  String? get phoneDigits => _phoneDigits;
  String? get displayName => _displayName;
  String? get role => _role;

  bool get isFinanceReader {
    final r = (_role ?? '').trim().toLowerCase();
    return r == 'finance' || r == 'auditor' || r == 'superadmin';
  }

  bool get isSuperAdmin {
    final r = (_role ?? '').trim().toLowerCase();
    return r == 'superadmin';
  }

  /// Operatsion admin (kundalik boshqaruv).
  bool get isOpsAdmin {
    final r = (_role ?? '').trim().toLowerCase();
    return r == 'admin' || r == 'superadmin' || r == 'dispatcher';
  }

  /// Foydalanuvchilar bo'limi (rol berish).
  bool get canManageUsers {
    final r = (_role ?? '').trim().toLowerCase();
    return r == 'admin' || r == 'superadmin';
  }

  /// Privileged rollar: finance / auditor / admin / superadmin.
  bool get canAssignPrivilegedRoles => isSuperAdmin;

  /// UI yorliq.
  String get roleDisplayLabel {
    switch ((_role ?? '').trim().toLowerCase()) {
      case 'superadmin':
        return 'Super Admin';
      case 'admin':
        return 'Admin';
      case 'finance':
        return 'Buxgalter';
      case 'auditor':
        return 'Auditor';
      case 'dispatcher':
        return 'Dispatcher';
      case 'seller':
        return 'Sotuvchi';
      default:
        return _role ?? 'user';
    }
  }

  static bool _isPanelRole(String? role) {
    final r = (role ?? '').trim().toLowerCase();
    return r == 'admin' ||
        r == 'superadmin' ||
        r == 'dispatcher' ||
        r == 'finance' ||
        r == 'auditor';
  }

  static List<String> _userDocIdCandidates(String rawPhone) =>
      fmt.userDocIdCandidates(rawPhone);

  Future<DocumentSnapshot<Map<String, dynamic>>?> _findUserDoc(
      String rawPhone) async {
    for (final id in _userDocIdCandidates(rawPhone)) {
      final snap = await _db.collection('users').doc(id).get();
      if (snap.exists) return snap;
    }
    return null;
  }

  Future<String?> _savedPhoneRaw() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPhoneKey);
  }

  /// Brauzer sessiyasi + saqlangan telefon — SMSsiz qayta kirish.
  Future<void> restoreSession() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await user.getIdToken(true);
        var rawPhone = user.phoneNumber ?? '';
        if (rawPhone.isEmpty) {
          final claims = await user.getIdTokenResult();
          rawPhone = (claims.claims?['phone_number'] as String?) ?? '';
        }
        if (rawPhone.isNotEmpty) {
          final snap = await _findUserDoc(rawPhone);
          if (snap != null && _isPanelRole(snap.data()?['role'] as String?)) {
            await _applyAdminSession(rawPhone: rawPhone, snap: snap);
            return;
          }
        }
      } catch (_) {
        await _auth.signOut();
      }
    }

    final saved = await _savedPhoneRaw();
    if (saved != null && saved.isNotEmpty) {
      final err = await signInWithPhonePasswordless(saved);
      if (err == null) return;
    }
  }

  /// Panel roli bor telefon: SMSsiz — `adminWebSignIn` → custom token.
  Future<String?> signInWithPhonePasswordless(String rawPhone) async {
    final digits = fmt.phoneDigits(rawPhone);
    if (digits.length < 9) {
      return 'Telefon raqamini to\'liq kiriting';
    }
    isVerifyingOtp = true;
    otpError = null;
    notifyListeners();
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('adminWebSignIn');
      final result = await callable.call<Map<String, dynamic>>({
        'phone': digits,
      });
      final data = result.data;
      final token = data['token'] as String?;
      if (token == null || token.isEmpty) {
        return 'Kirish tokeni olinmadi';
      }
      await _auth.signInWithCustomToken(token);
      await _auth.currentUser?.getIdToken(true);
      final snap = await _findUserDoc(rawPhone);
      if (snap == null) {
        await _auth.signOut();
        return 'Bu telefon Firestore\'da topilmadi.';
      }
      final role = snap.data()?['role'] as String? ?? '';
      if (!_isPanelRole(role)) {
        await _auth.signOut();
        return 'Siz admin emassiz (hozirgi rol: ${role.isEmpty ? 'user' : role}).';
      }
      await _applyAdminSession(rawPhone: rawPhone, snap: snap);
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? e.code;
    } on FirebaseAuthException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return 'Xatolik: $e';
    } finally {
      isVerifyingOtp = false;
      notifyListeners();
    }
  }

  /// Maxfiy kod (PIN) bilan kirish — telefonsiz.
  /// `adminWebSignInWithCode` CF kodni tekshiradi va ishonchli admin
  /// operator uchun custom token qaytaradi.
  Future<String?> signInWithCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      return 'Kirish kodini kiriting';
    }
    isVerifyingOtp = true;
    otpError = null;
    notifyListeners();
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('adminWebSignInWithCode');
      final result = await callable.call<Map<String, dynamic>>({
        'code': trimmed,
      });
      final data = result.data;
      final token = data['token'] as String?;
      final rawPhone = (data['phone'] as String?) ?? '';
      if (token == null || token.isEmpty) {
        return 'Kirish tokeni olinmadi';
      }
      await _auth.signInWithCustomToken(token);
      await _auth.currentUser?.getIdToken(true);
      final snap = await _findUserDoc(rawPhone);
      if (snap == null) {
        await _auth.signOut();
        return 'Admin operator Firestore\'da topilmadi.';
      }
      final role = snap.data()?['role'] as String? ?? '';
      if (!_isPanelRole(role)) {
        await _auth.signOut();
        return 'Bu hisob admin emas.';
      }
      await _applyAdminSession(rawPhone: rawPhone, snap: snap);
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? e.code;
    } on FirebaseAuthException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return 'Xatolik: $e';
    } finally {
      isVerifyingOtp = false;
      notifyListeners();
    }
  }

  Future<void> _applyAdminSession({
    required String rawPhone,
    required DocumentSnapshot<Map<String, dynamic>> snap,
  }) async {
    final digits = fmt.phoneDigits(rawPhone);
    _phone = digits.startsWith('+') ? digits : '+$digits';
    _phoneDigits = snap.id;
    _displayName = (snap.data()?['name'] as String?) ?? '';
    _role = (snap.data()?['role'] as String?) ?? '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPhoneKey, _phone!);
    await prefs.setString('user_phone', _phone!);
    await prefs.setString('user_role', _role!.isNotEmpty ? _role! : 'admin');
    await prefs.setString('user_name', _displayName ?? '');
    notifyListeners();
  }

  /// Telefon bilan parolsiz kirish (SMS/OTP yo'q).
  Future<bool> sendOtp(String rawPhone) async {
    final digits = fmt.phoneDigits(rawPhone);
    if (digits.length < 9) {
      otpError = 'Telefon raqamini to\'liq kiriting';
      notifyListeners();
      return false;
    }
    isSendingOtp = true;
    otpError = null;
    notifyListeners();
    final err = await signInWithPhonePasswordless(rawPhone);
    isSendingOtp = false;
    if (err != null) {
      otpError = err;
      notifyListeners();
      return false;
    }
    notifyListeners();
    return true;
  }

  Future<void> logout() async {
    if (_auth.currentUser != null) {
      await _auth.signOut();
    }
    _phone = null;
    _phoneDigits = null;
    _displayName = null;
    otpError = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPhoneKey);
    await prefs.remove('user_phone');
    await prefs.remove('user_role');
    await prefs.remove('user_name');
    notifyListeners();
  }
}
