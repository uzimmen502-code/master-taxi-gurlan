import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/formatters.dart' as fmt;

/// Admin web auth: [trustedAdminPhoneDigits] — SMSsiz (CF custom token).
/// Boshqa raqamlar — Firebase Phone OTP.
class AdminAuthService extends ChangeNotifier {
  AdminAuthService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const _kPhoneKey = 'admin_web_phone';

  /// Yagona SMSsiz admin web operator raqami.
  static const String trustedAdminPhoneDigits = '998912778777';

  String? _phone;
  String? _phoneDigits;
  String? _displayName;

  String _verificationId = '';
  int? _resendToken;
  bool isSendingOtp = false;
  bool isVerifyingOtp = false;
  String? otpError;
  bool otpSent = false;

  bool get isLoggedIn => _phoneDigits != null && _phoneDigits!.isNotEmpty;

  static bool isTrustedAdminPhone(String rawPhone) =>
      fmt.phoneDigits(rawPhone) == trustedAdminPhoneDigits;

  String? get phone => _phone;
  String? get phoneDigits => _phoneDigits;
  String? get displayName => _displayName;

  static bool _isAdminRole(String? role) {
    final r = (role ?? '').trim().toLowerCase();
    return r == 'admin' || r == 'superadmin' || r == 'dispatcher';
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
          if (snap != null && _isAdminRole(snap.data()?['role'] as String?)) {
            await _applyAdminSession(rawPhone: rawPhone, snap: snap);
            return;
          }
        }
      } catch (_) {
        await _auth.signOut();
      }
    }

    final saved = await _savedPhoneRaw();
    if (saved != null && saved.isNotEmpty && isTrustedAdminPhone(saved)) {
      final err = await signInWithTrustedPhone(saved);
      if (err == null) return;
    }
  }

  /// Trusted raqam: SMSsiz — `adminWebSignIn` → custom token → Firestore role.
  Future<String?> signInWithTrustedPhone(String rawPhone) async {
    if (!isTrustedAdminPhone(rawPhone)) {
      return 'Bu panel uchun faqat ishonchli operator raqami';
    }
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
      final snap = await _findUserDoc(rawPhone);
      if (snap == null) {
        await _auth.signOut();
        return 'Bu telefon Firestore\'da topilmadi.';
      }
      final role = snap.data()?['role'] as String? ?? '';
      if (!_isAdminRole(role)) {
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

  Future<void> _applyAdminSession({
    required String rawPhone,
    required DocumentSnapshot<Map<String, dynamic>> snap,
  }) async {
    final digits = fmt.phoneDigits(rawPhone);
    _phone = digits.startsWith('+') ? digits : '+$digits';
    _phoneDigits = snap.id;
    _displayName = (snap.data()?['name'] as String?) ?? '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPhoneKey, _phone!);
    await prefs.setString('user_phone', _phone!);
    await prefs.setString('user_role', 'admin');
    await prefs.setString('user_name', _displayName ?? '');
    notifyListeners();
  }

  /// Telefon: trusted → SMSsiz; boshqa → OTP.
  Future<bool> sendOtp(String rawPhone) async {
    final digits = fmt.phoneDigits(rawPhone);
    if (digits.length < 9) {
      otpError = 'Telefon raqamini to\'liq kiriting';
      notifyListeners();
      return false;
    }
    if (isTrustedAdminPhone(rawPhone)) {
      isSendingOtp = true;
      otpError = null;
      notifyListeners();
      final err = await signInWithTrustedPhone(rawPhone);
      isSendingOtp = false;
      if (err != null) {
        otpError = err;
        notifyListeners();
        return false;
      }
      notifyListeners();
      return true;
    }

    isSendingOtp = true;
    otpError = null;
    otpSent = false;
    notifyListeners();
    final completer = Completer<bool>();
    await _auth.verifyPhoneNumber(
      phoneNumber: '+$digits',
      forceResendingToken: _resendToken,
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _auth.signInWithCredential(credential);
        isSendingOtp = false;
        otpSent = true;
        notifyListeners();
        if (!completer.isCompleted) completer.complete(true);
      },
      verificationFailed: (FirebaseAuthException e) {
        otpError = _otpErrorMsg(e.code);
        isSendingOtp = false;
        notifyListeners();
        if (!completer.isCompleted) completer.complete(false);
      },
      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        _resendToken = resendToken;
        isSendingOtp = false;
        otpSent = true;
        notifyListeners();
        if (!completer.isCompleted) completer.complete(true);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
      timeout: const Duration(seconds: 60),
    );
    return completer.future;
  }

  Future<String?> verifyOtpAndSignIn(String rawPhone, String smsCode) async {
    if (_verificationId.isEmpty) {
      return 'Avval SMS yuboring';
    }
    isVerifyingOtp = true;
    otpError = null;
    notifyListeners();
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: smsCode.trim(),
      );
      await _auth.signInWithCredential(credential);
      final snap = await _findUserDoc(rawPhone);
      if (snap == null) {
        await _auth.signOut();
        return 'Bu telefon Firestore\'da topilmadi.';
      }
      final role = snap.data()?['role'] as String? ?? '';
      if (!_isAdminRole(role)) {
        await _auth.signOut();
        return 'Siz admin emassiz (hozirgi rol: ${role.isEmpty ? 'user' : role}).';
      }
      await _applyAdminSession(rawPhone: rawPhone, snap: snap);
      return null;
    } on FirebaseAuthException catch (e) {
      return _otpErrorMsg(e.code);
    } catch (e) {
      return 'Xatolik: $e';
    } finally {
      isVerifyingOtp = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    if (_auth.currentUser != null) {
      await _auth.signOut();
    }
    _phone = null;
    _phoneDigits = null;
    _displayName = null;
    _verificationId = '';
    otpSent = false;
    otpError = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPhoneKey);
    await prefs.remove('user_phone');
    await prefs.remove('user_role');
    await prefs.remove('user_name');
    notifyListeners();
  }

  String _otpErrorMsg(String code) => switch (code) {
        'invalid-verification-code' => 'SMS kod noto\'g\'ri.',
        'session-expired' => 'Muddat tugadi. Qayta yuboring.',
        'invalid-phone-number' => 'Telefon raqami noto\'g\'ri.',
        'too-many-requests' => 'Ko\'p urinish. Keyinroq.',
        _ => 'Xatolik: $code',
      };
}
