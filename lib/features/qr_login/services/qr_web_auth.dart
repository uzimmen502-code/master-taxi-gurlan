import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/firebase_functions_client.dart';
import '../../../core/utils/formatters.dart';
import '../data/qr_login_api.dart';
import '../data/qr_web_session_store.dart';

/// Web: QR орқали кириш сессиясини якунлаш, жим янгилаш ва чиқиш (эга 2026-11-28).
class QrWebAuth {
  QrWebAuth._();

  /// `qrLoginConsume` натижаси → Firebase sign-in + prefs (AuthRestore/ZoneGate шу калитларни ўқийди).
  static Future<void> completeSignIn(QrConsumeResult r) async {
    final phone = canonicalPhoneId(r.phone);
    await FirebaseAuth.instance.signInWithCustomToken(r.customToken);
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userId', phone);
    await prefs.setString('user_phone', phone);
    await prefs.setBool('onboarding_done', true);
    await prefs.setBool('phone_reverified', true);
    try {
      final u = await FirebaseFirestore.instance.collection('users').doc(phone).get();
      final name = ((u.data() ?? const {})['name'] ?? '').toString().trim();
      if (name.isNotEmpty) {
        await prefs.setString('user_name', name);
        await prefs.setString('userName', name);
      }
    } catch (_) {}
    await QrWebSessionStore.save(QrWebSession(
      webSessionId: r.webSessionId,
      renewSecret: r.renewSecret,
      phone: phone,
      expiresAtMs: r.sessionExpiresAtMs,
    ));
    unawaited(QrWebSessionGuard.instance.start());
  }

  /// Сақланган web сессия билан янги token (refresh token бекор қилинганда).
  /// `true` — кирилди; сессия тугаган бўлса — store тозаланади, `false`.
  static Future<bool> tryRenew({FirebaseFunctions? functions}) async {
    final s = await QrWebSessionStore.load();
    if (s == null) return false;
    if (s.expiredAt(DateTime.now().millisecondsSinceEpoch)) {
      await QrWebSessionStore.clear();
      return false;
    }
    try {
      final r = await (functions ?? AvaFunctions.auth)
          .httpsCallable('qrWebSessionRenew', options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
          .call<Object?>({'webSessionId': s.webSessionId, 'renewSecret': s.renewSecret});
      final d = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : <String, dynamic>{};
      final token = (d['customToken'] ?? '').toString();
      if (token.isEmpty) return false;
      await FirebaseAuth.instance.signInWithCustomToken(token);
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      return FirebaseAuth.instance.currentUser != null;
    } on FirebaseFunctionsException catch (e) {
      final d = e.details;
      final code = d is Map ? (d['code'] ?? '').toString() : '';
      if (code == 'QR_WEB_SESSION_INVALID' || code == 'QR_LOGIN_DISABLED') {
        await QrWebSessionStore.clear();
      }
      return false;
    } catch (e) {
      debugPrint('[qr_web] renew: $e');
      return false;
    }
  }

  /// Web'даги «Чиқиш»: шу сессия серверда бекор (renewSecret билан), кейин маҳаллий тозалаш.
  /// Телефон ва бошқа сессияларга тегмайди. Хатода ҳам маҳаллий чиқиш давом этади.
  static Future<void> selfLogout({FirebaseFunctions? functions}) async {
    QrWebSessionGuard.instance.stop();
    final s = await QrWebSessionStore.load();
    if (s == null) return;
    try {
      await (functions ?? AvaFunctions.auth)
          .httpsCallable('qrWebSessionRevoke', options: HttpsCallableOptions(timeout: const Duration(seconds: 15)))
          .call<Object?>({'webSessionId': s.webSessionId, 'renewSecret': s.renewSecret});
    } catch (e) {
      debugPrint('[qr_web] self revoke: $e');
    }
    await QrWebSessionStore.clear();
  }
}

/// Web: сессия ҳолатини тинглайди. Телефондан «Чиқиш» → `qr_web_sessions/{id}.status` ≠ active
/// → дарҳол signOut. Firebase сессия узилса (refresh token бекор) → renewSecret билан жим тиклаш.
class QrWebSessionGuard {
  QrWebSessionGuard._();
  static final QrWebSessionGuard instance = QrWebSessionGuard._();

  /// Сессия тугаганда (main.dart навигацияни шу ерга улайди).
  VoidCallback? onEnded;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;
  String _watching = '';
  bool _renewing = false;
  DateTime _lastRenewAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isRunning => _authSub != null;

  Future<void> start() async {
    if (!kIsWeb) return;
    final s = await QrWebSessionStore.load();
    if (s == null) return;
    stop();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        _docSub?.cancel();
        _docSub = null;
        _watching = '';
        unawaited(_renew());
      } else {
        _watchDoc(s.webSessionId);
      }
    });
  }

  void stop() {
    _authSub?.cancel();
    _authSub = null;
    _docSub?.cancel();
    _docSub = null;
    _watching = '';
  }

  void _watchDoc(String id) {
    if (_watching == id && _docSub != null) return;
    _docSub?.cancel();
    _watching = id;
    _docSub = FirebaseFirestore.instance.collection('qr_web_sessions').doc(id).snapshots().listen(
      (snap) {
        final status = (snap.data()?['status'] ?? '').toString();
        if (!snap.exists || status != 'active') unawaited(_end());
      },
      onError: (_) {
        // Рухсат йўқ (масалан бошқа рақам билан кирилган) — тинглаш тўхтайди, сессияга тегилмайди.
        _docSub = null;
        _watching = '';
      },
    );
  }

  Future<void> _renew() async {
    if (_renewing) return;
    final now = DateTime.now();
    if (now.difference(_lastRenewAt) < const Duration(seconds: 20)) return;
    _renewing = true;
    _lastRenewAt = now;
    try {
      final ok = await QrWebAuth.tryRenew();
      if (!ok && await QrWebSessionStore.load() == null) await _end();
    } finally {
      _renewing = false;
    }
  }

  Future<void> _end() async {
    stop();
    await QrWebSessionStore.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('phone_reverified', false);
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    onEnded?.call();
  }
}
