import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/firebase_functions_client.dart';
import '../../../core/utils/formatters.dart';
import '../../../repositories/device_binding_repository.dart';
import '../../../services/device_fingerprint_service.dart';

/// Сервер хатоси: ички код (`details.code`) — UI уни l10n калитига айлантиради.
class QrLoginException implements Exception {
  const QrLoginException(this.code);
  final String code;
  @override
  String toString() => 'QrLoginException($code)';
}

class QrStartResult {
  const QrStartResult({
    required this.sid,
    required this.secret,
    required this.watchId,
    required this.qrPayload,
    required this.expiresAtMs,
  });
  final String sid;
  final String secret;
  final String watchId;
  final String qrPayload;
  final int expiresAtMs;
}

class QrPeekResult {
  const QrPeekResult({
    required this.sid,
    this.browserLabel = '',
    this.approxCity = '',
    this.createdAtMs = 0,
    this.expiresAtMs = 0,
    this.outflowBlockHours = 0,
  });
  final String sid;
  final String browserLabel;
  final String approxCity;
  final int createdAtMs;
  final int expiresAtMs;
  final int outflowBlockHours;
}

class QrConsumeResult {
  const QrConsumeResult({
    required this.customToken,
    required this.phone,
    required this.webSessionId,
    required this.renewSecret,
    this.sessionExpiresAtMs = 0,
  });
  final String customToken;
  final String phone;
  final String webSessionId;
  final String renewSecret;
  final int sessionExpiresAtMs;
}

class QrWebSessionItem {
  const QrWebSessionItem({
    required this.webSessionId,
    this.browserLabel = '',
    this.approxCity = '',
    this.createdAtMs = 0,
    this.lastActiveAtMs = 0,
  });
  final String webSessionId;
  final String browserLabel;
  final String approxCity;
  final int createdAtMs;
  final int lastActiveAtMs;
}

class QrWebSessionsList {
  const QrWebSessionsList({required this.enabled, required this.canManage, required this.items});
  final bool enabled;
  final bool canManage;
  final List<QrWebSessionItem> items;
}

/// Callable'лар интерфейси (виджет тестлари сохта нусха беради — Firebase'сиз).
abstract class QrLoginApi {
  // ── Web (кирмаган браузер) ──
  Future<bool> probeEnabled();
  Future<QrStartResult> start();
  Stream<String> watch(String watchId);
  Future<QrConsumeResult> consume({required String sid, required String secret});

  // ── Телефон (боғланган қурилма) ──
  Future<QrPeekResult> peek(String sid);
  Future<void> decide(String sid, {required bool approve});
  Future<QrWebSessionsList> listSessions();

  /// [webSessionId] ёки [all]. Сервер refresh token'ларни бекор қилса — шу телефон
  /// ўз боғланиши билан дарҳол жим қайта киради (ичида).
  Future<int> revoke({String? webSessionId, bool all = false});
}

String _codeOf(Object e) {
  if (e is FirebaseFunctionsException) {
    final d = e.details;
    if (d is Map && d['code'] is String) return d['code'] as String;
    return e.code;
  }
  return 'UNKNOWN';
}

Map<String, dynamic> _map(Object? data) =>
    data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};

int _int(Object? v) => (v is num) ? v.toInt() : 0;
String _str(Object? v) => (v ?? '').toString();

/// Firebase (`europe-west1` auth callable'лари) орқали.
class FirebaseQrLoginApi implements QrLoginApi {
  FirebaseQrLoginApi({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
    DeviceFingerprintService? fingerprint,
  })  : _functions = functions ?? AvaFunctions.auth,
        _db = firestore ?? FirebaseFirestore.instance,
        _fingerprint = fingerprint ?? DeviceFingerprintService();

  final FirebaseFunctions _functions;
  final FirebaseFirestore _db;
  final DeviceFingerprintService _fingerprint;
  DeviceFingerprintSnapshot? _snapshot;

  /// Бир жараёнда бир марта (профил қатори кўриниши учун; §37).
  static QrWebSessionsList? cachedList;

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> payload) async {
    try {
      final r = await _functions
          .httpsCallable(name, options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
          .call<Object?>(payload);
      return _map(r.data);
    } catch (e) {
      throw QrLoginException(_codeOf(e));
    }
  }

  Future<Map<String, dynamic>> _deviceProof() async {
    _snapshot ??= await _fingerprint.collect();
    return {
      'deviceFingerprintHash': DeviceBindingRepository.normalizeFingerprintHash(_snapshot!.hash),
      'fingerprint': Map<String, String>.from(_snapshot!.components),
    };
  }

  @override
  Future<bool> probeEnabled() async {
    try {
      final d = await _call('qrLoginStart', {'probe': true});
      return d['enabled'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<QrStartResult> start() async {
    final d = await _call('qrLoginStart', {});
    return QrStartResult(
      sid: _str(d['sid']),
      secret: _str(d['secret']),
      watchId: _str(d['watchId']),
      qrPayload: _str(d['qrPayload']),
      expiresAtMs: _int(d['expiresAtMs']),
    );
  }

  @override
  Stream<String> watch(String watchId) => _db
      .collection('qr_login_watch')
      .doc(watchId)
      .snapshots()
      .map((s) => _str(s.data()?['status']));

  @override
  Future<QrConsumeResult> consume({required String sid, required String secret}) async {
    final d = await _call('qrLoginConsume', {'sid': sid, 'secret': secret});
    return QrConsumeResult(
      customToken: _str(d['customToken']),
      phone: _str(d['phone']),
      webSessionId: _str(d['webSessionId']),
      renewSecret: _str(d['renewSecret']),
      sessionExpiresAtMs: _int(d['sessionExpiresAtMs']),
    );
  }

  @override
  Future<QrPeekResult> peek(String sid) async {
    final d = await _call('qrLoginPeek', {'sid': sid, ...await _deviceProof()});
    return QrPeekResult(
      sid: sid,
      browserLabel: _str(d['browserLabel']),
      approxCity: _str(d['approxCity']),
      createdAtMs: _int(d['createdAtMs']),
      expiresAtMs: _int(d['expiresAtMs']),
      outflowBlockHours: _int(d['outflowBlockHours']),
    );
  }

  @override
  Future<void> decide(String sid, {required bool approve}) async {
    await _call('qrLoginApprove', {'sid': sid, 'approve': approve, ...await _deviceProof()});
  }

  @override
  Future<QrWebSessionsList> listSessions() async {
    final d = await _call('qrWebSessionsList', await _deviceProof());
    final raw = d['items'];
    final items = <QrWebSessionItem>[
      if (raw is List)
        for (final e in raw)
          if (e is Map && _str(e['webSessionId']).isNotEmpty)
            QrWebSessionItem(
              webSessionId: _str(e['webSessionId']),
              browserLabel: _str(e['browserLabel']),
              approxCity: _str(e['approxCity']),
              createdAtMs: _int(e['createdAtMs']),
              lastActiveAtMs: _int(e['lastActiveAtMs']),
            ),
    ];
    final out = QrWebSessionsList(enabled: d['enabled'] == true, canManage: d['canManage'] == true, items: items);
    cachedList = out;
    return out;
  }

  @override
  Future<int> revoke({String? webSessionId, bool all = false}) async {
    final d = await _call('qrWebSessionRevoke', {
      if (webSessionId != null) 'webSessionId': webSessionId,
      if (all) 'all': true,
      ...await _deviceProof(),
    });
    if (d['reauthRequired'] == true) {
      await _reauthThisPhone();
    }
    return _int(d['revoked']);
  }

  /// Сервер ҳисобнинг refresh token'ларини бекор қилди — шу (боғланган) телефон дарҳол
  /// янги token олади (аксинча ≤1 соатдан кейин сессия узилиб қоларди).
  Future<void> _reauthThisPhone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = phoneDigits(prefs.getString('user_phone') ?? '');
      if (phone.length < 12) return;
      _snapshot ??= await _fingerprint.collect();
      final token = await DeviceBindingRepository().trustedTokenForThisDevice(phone: phone, snapshot: _snapshot!);
      if (token == null || token.isEmpty) return;
      await FirebaseAuth.instance.signInWithCustomToken(token);
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
    } catch (_) {
      // Кейинги очилишда AuthRestoreScreen жим тиклайди.
    }
  }
}
