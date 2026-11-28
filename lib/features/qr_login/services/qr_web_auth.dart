import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/firebase_functions_client.dart';
import '../../../core/utils/formatters.dart';
import '../../../utils/locale_utils.dart';
import '../data/qr_login_api.dart';
import '../data/qr_web_session_store.dart';

/// Web: QR орқали кириш (эга 2026-11-28).
///
/// «Ҳар сафар кирганда янгидан сканерлаш»: Firebase Auth SESSION persistence (sessionStorage) —
/// вкладка/браузер ёпилса ёки компьютер ўчиб-ёнса кириш йўқолади; жим қайта кириш ЙЎҚ.
/// Очиқ вкладкада token'ни Firebase SDK ўзи янгилайди (refresh token шу вкладкада), сервер
/// сессияси heartbeat билан яшайди ([QrWebSessionGuard]).
class QrWebAuth {
  QrWebAuth._();

  /// `qrLoginConsume` натижаси → Firebase sign-in (SESSION) + prefs (AuthRestore/ZoneGate шу калитларни ўқийди).
  static Future<void> completeSignIn(QrConsumeResult r) async {
    final phone = canonicalPhoneId(r.phone);
    if (kIsWeb) {
      // Браузер ёпилса чиқсин (LOCAL эмас). Аввалги (масалан анонм) сессия ҳам шу сақлашга ўтади.
      await FirebaseAuth.instance.setPersistence(Persistence.SESSION);
    }
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
      phone: phone,
      heartbeatIntervalMs: r.heartbeatIntervalMs,
    ));
    unawaited(QrWebSessionGuard.instance.start());
  }

  /// Браузер қайта очилди, Firebase сессия йўқ, лекин prefs'да QR кириш излари бор → тозалаш
  /// (тил сақланади). `true` — тозаланди (чақирувчи кириш экранига ўтади: янги QR скан).
  static Future<bool> clearAfterBrowserRestart() async {
    if (!kIsWeb || !await QrWebSessionStore.wasQrLogin()) return false;
    final prefs = await SharedPreferences.getInstance();
    await LocaleUtils.clearPrefsKeepingLanguage(prefs);
    await QrWebSessionStore.clear();
    return true;
  }

  /// Web'даги «Чиқиш»: шу сессия серверда бекор (auth + сессия ID), кейин маҳаллий тозалаш.
  /// Телефонга тегмайди. Хатода ҳам маҳаллий чиқиш давом этади.
  static Future<void> selfLogout({FirebaseFunctions? functions}) async {
    QrWebSessionGuard.instance.stop();
    final s = await QrWebSessionStore.load();
    if (s == null) return;
    try {
      await (functions ?? AvaFunctions.auth)
          .httpsCallable('qrWebSessionRevoke', options: HttpsCallableOptions(timeout: const Duration(seconds: 15)))
          .call<Object?>({'self': true, 'webSessionId': s.webSessionId});
    } catch (e) {
      debugPrint('[qr_web] self revoke: $e');
    }
    await QrWebSessionStore.clear();
  }
}

/// Web: сессия ҳолатини тинглайди ва heartbeat юборади.
/// - Телефондан «Компьютерни тизимдан чиқариш» / бошқа компьютерда кириш → `qr_web_sessions/{id}`
///   ≠ active → дарҳол signOut.
/// - Heartbeat рад этилса (жим қолган, бекор, босқич OFF) → signOut.
/// - Firebase сессия узилса (refresh token бекор) → signOut (жим тиклаш ЙЎҚ).
class QrWebSessionGuard {
  QrWebSessionGuard._();
  static final QrWebSessionGuard instance = QrWebSessionGuard._();

  /// Сессия тугаганда (main.dart навигацияни шу ерга улайди).
  VoidCallback? onEnded;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;
  Timer? _heartbeat;
  String _watching = '';
  bool _ending = false;

  bool get isRunning => _authSub != null;

  Future<void> start() async {
    if (!kIsWeb) return;
    final s = await QrWebSessionStore.load();
    if (s == null) return;
    stop();
    _ending = false;
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        unawaited(_end());
      } else {
        _watchDoc(s.webSessionId);
      }
    });
    // Дарҳол бир марта: браузер «вкладкаларни тиклаш» билан sessionStorage'ни қайтарган бўлса ҳам,
    // сервер сессияси жимликдан тугаган бўлса — шу заҳоти чиқилади.
    unawaited(_beat(s.webSessionId));
    final ms = s.heartbeatIntervalMs.clamp(60 * 1000, 30 * 60 * 1000);
    _heartbeat = Timer.periodic(Duration(milliseconds: ms), (_) => unawaited(_beat(s.webSessionId)));
  }

  void stop() {
    _authSub?.cancel();
    _authSub = null;
    _docSub?.cancel();
    _docSub = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _watching = '';
  }

  Future<void> _beat(String id) async {
    if (FirebaseAuth.instance.currentUser == null) return;
    try {
      await AvaFunctions.auth
          .httpsCallable('qrWebSessionHeartbeat', options: HttpsCallableOptions(timeout: const Duration(seconds: 20)))
          .call<Object?>({'webSessionId': id});
    } on FirebaseFunctionsException catch (e) {
      final d = e.details;
      final code = d is Map ? (d['code'] ?? '').toString() : '';
      if (code == 'QR_WEB_SESSION_INVALID' || code == 'QR_LOGIN_DISABLED') unawaited(_end());
      // Тармоқ хатоси — кейинги уриниш; сервер 15 дақ. жимликдан кейин ўзи тугатади.
    } catch (e) {
      debugPrint('[qr_web] heartbeat: $e');
    }
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
        // Рухсат йўқ (масалан бошқа рақам билан кирилган) — тинглаш тўхтайди.
        _docSub = null;
        _watching = '';
      },
    );
  }

  Future<void> _end() async {
    if (_ending) return;
    _ending = true;
    stop();
    await QrWebSessionStore.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await LocaleUtils.clearPrefsKeepingLanguage(prefs);
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    onEnded?.call();
  }
}
