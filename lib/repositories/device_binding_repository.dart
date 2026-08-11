import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../core/firebase_functions_client.dart';
import '../core/utils/formatters.dart';
import '../services/device_fingerprint_service.dart';

/// SHA-256 fingerprint hash: 64 hex belgi.
final RegExp fingerprintHashPattern = RegExp(r'^[a-f0-9]{64}$');

enum DeviceBindingStatus {
  trustedDevice,
  needsVerification,
  deviceBoundOtherPhone,
  phoneBoundOtherDevice,
  blocked,
  unknown,
}

class DeviceBindingCheckResult {
  const DeviceBindingCheckResult({
    required this.status,
    this.customToken,
    this.message,
    this.failedAttempts = 0,
    this.selfServeAvailable = false,
    this.oldDeviceLabel = '',
    this.selfServeHint = '',
    this.retryAfterMs = 0,
  });

  final DeviceBindingStatus status;
  final String? customToken;
  final String? message;
  final int failedAttempts;
  final bool selfServeAvailable;
  final String oldDeviceLabel;
  final String selfServeHint;
  final int retryAfterMs;

  bool get skipSms => status == DeviceBindingStatus.trustedDevice;
}

class DeviceTransferRequestResult {
  const DeviceTransferRequestResult({
    required this.status,
    required this.requestId,
    this.expiresAtMs,
    this.oldDeviceLabel = '',
    this.message,
  });

  final String status;
  final String requestId;
  final int? expiresAtMs;
  final String oldDeviceLabel;
  final String? message;
}

class DeviceTransferPendingItem {
  const DeviceTransferPendingItem({
    required this.requestId,
    this.newDeviceLabel = '',
    this.expiresAtMs,
  });

  final String requestId;
  final String newDeviceLabel;
  final int? expiresAtMs;
}

class DeviceBindingRepository {
  DeviceBindingRepository({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
  })  : _functions = functions ?? AvaFunctions.auth,
        _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFunctions _functions;
  final FirebaseFirestore _db;

  /// Yangi tizim: faqat 64 hex SHA-256 hash.
  static bool isValidFingerprintHash(String value) {
    return fingerprintHashPattern.hasMatch(value.trim().toLowerCase());
  }

  static String normalizeFingerprintHash(String value) =>
      value.trim().toLowerCase();

  Future<Map<String, dynamic>?> getBinding(String fingerprintHash) async {
    if (!isValidFingerprintHash(fingerprintHash)) return null;
    final doc = await _db
        .collection('device_bindings')
        .doc(normalizeFingerprintHash(fingerprintHash))
        .get();
    return doc.exists ? doc.data() : null;
  }

  /// `device_bindings/{hash}` — faqat hash-format ID; eski ID lar hisobga olinmaydi.
  Future<bool> isDeviceBound(DeviceFingerprintSnapshot snapshot) async {
    final hash = normalizeFingerprintHash(snapshot.hash);
    if (!isValidFingerprintHash(hash)) {
      return false;
    }
    final snap = await _db.collection('device_bindings').doc(hash).get();
    return snap.exists;
  }

  /// Cold start / region warmup — til ekranida fonda chaqiriladi.
  Future<void> warmup() async {
    final opts = HttpsCallableOptions(timeout: const Duration(seconds: 15));
    Future<void> ping(String name) async {
      try {
        await _functions
            .httpsCallable(name, options: opts)
            .call(<String, dynamic>{'warmup': true});
      } catch (_) {}
    }

    await Future.wait([
      ping('checkDeviceBinding'),
      ping('createPhoneSession'),
    ]);
  }

  /// Bindingdan keyin Auth custom token.
  Future<String> createPhoneSession({
    required String phone,
    required DeviceFingerprintSnapshot snapshot,
  }) async {
    final hash = normalizeFingerprintHash(snapshot.hash);
    if (!isValidFingerprintHash(hash)) {
      throw StateError('deviceFingerprintHash noto\'g\'ri');
    }
    final callable = _functions.httpsCallable(
      'createPhoneSession',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
    );
    final result = await callable.call<Map<String, dynamic>>({
      'phone': phoneDigits(phone),
      'deviceFingerprintHash': hash,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final token = (data['customToken'] as String?)?.trim() ?? '';
    if (token.isEmpty) {
      throw StateError('customToken bo\'sh');
    }
    return token;
  }

  Future<DeviceBindingCheckResult> checkDeviceBinding({
    required String phone,
    required DeviceFingerprintSnapshot snapshot,
  }) async {
    final hash = normalizeFingerprintHash(snapshot.hash);
    if (!isValidFingerprintHash(hash)) {
      throw StateError('deviceFingerprintHash noto\'g\'ri');
    }

    final digits = phoneDigits(phone);
    final payload = <String, dynamic>{
      'phone': digits,
      'deviceFingerprintHash': hash,
      'fingerprint': Map<String, String>.from(snapshot.components),
    };

    Future<DeviceBindingCheckResult> invoke(Duration timeout) async {
      final callable = _functions.httpsCallable(
        'checkDeviceBinding',
        options: HttpsCallableOptions(timeout: timeout),
      );
      final result = await callable.call<Map<String, dynamic>>(payload);
      final data = Map<String, dynamic>.from(result.data as Map);
      return _parseCheckResult(data);
    }

    try {
      return await invoke(const Duration(seconds: 25));
    } on FirebaseFunctionsException catch (e) {
      // Qisqa timeout / cold start: tezroq ikkinchi urinish.
      if (e.code == 'deadline-exceeded') {
        return await invoke(const Duration(seconds: 45));
      }
      rethrow;
    }
  }

  Future<DeviceTransferRequestResult> requestDeviceTransfer({
    required String phone,
    required DeviceFingerprintSnapshot snapshot,
  }) async {
    final hash = normalizeFingerprintHash(snapshot.hash);
    if (!isValidFingerprintHash(hash)) {
      throw StateError('deviceFingerprintHash noto\'g\'ri');
    }
    final callable = _functions.httpsCallable(
      'requestDeviceTransfer',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
    );
    final result = await callable.call<Map<String, dynamic>>({
      'phone': phoneDigits(phone),
      'deviceFingerprintHash': hash,
      'fingerprint': Map<String, String>.from(snapshot.components),
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return DeviceTransferRequestResult(
      status: (data['status'] ?? '').toString(),
      requestId: (data['requestId'] ?? '').toString(),
      expiresAtMs: (data['expiresAtMs'] as num?)?.toInt(),
      oldDeviceLabel: (data['oldDeviceLabel'] ?? '').toString(),
      message: data['message'] as String?,
    );
  }

  Future<DeviceTransferRequestResult> getDeviceTransferStatus({
    required String phone,
    required DeviceFingerprintSnapshot snapshot,
    required String requestId,
  }) async {
    final hash = normalizeFingerprintHash(snapshot.hash);
    final callable = _functions.httpsCallable(
      'getDeviceTransferStatus',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );
    final result = await callable.call<Map<String, dynamic>>({
      'phone': phoneDigits(phone),
      'deviceFingerprintHash': hash,
      'requestId': requestId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return DeviceTransferRequestResult(
      status: (data['status'] ?? '').toString(),
      requestId: (data['requestId'] ?? requestId).toString(),
      expiresAtMs: (data['expiresAtMs'] as num?)?.toInt(),
      oldDeviceLabel: (data['oldDeviceLabel'] ?? '').toString(),
    );
  }

  Future<void> respondDeviceTransfer({
    required String requestId,
    required bool approve,
    required DeviceFingerprintSnapshot snapshot,
  }) async {
    final hash = normalizeFingerprintHash(snapshot.hash);
    final callable = _functions.httpsCallable(
      'respondDeviceTransfer',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
    );
    await callable.call<Map<String, dynamic>>({
      'requestId': requestId,
      'approve': approve,
      'deviceFingerprintHash': hash,
    });
  }

  Future<List<DeviceTransferPendingItem>> listMyPendingDeviceTransfers({
    required DeviceFingerprintSnapshot snapshot,
  }) async {
    final hash = normalizeFingerprintHash(snapshot.hash);
    final callable = _functions.httpsCallable(
      'listMyPendingDeviceTransfers',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );
    final result = await callable.call<Map<String, dynamic>>({
      'deviceFingerprintHash': hash,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final raw = data['items'];
    if (raw is! List) return const [];
    return raw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return DeviceTransferPendingItem(
        requestId: (m['requestId'] ?? '').toString(),
        newDeviceLabel: (m['newDeviceLabel'] ?? '').toString(),
        expiresAtMs: (m['expiresAtMs'] as num?)?.toInt(),
      );
    }).where((e) => e.requestId.isNotEmpty).toList();
  }

  Future<void> registerDeviceBinding({
    required String phone,
    required DeviceFingerprintSnapshot snapshot,
    required String verifiedMethod,
    String? adminCode,
  }) async {
    final hash = normalizeFingerprintHash(snapshot.hash);
    if (!isValidFingerprintHash(hash)) {
      throw StateError('deviceFingerprintHash noto\'g\'ri');
    }

    final callable = _functions.httpsCallable(
      'registerDeviceBinding',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
    );
    final digits = phoneDigits(phone);
    await callable.call<Map<String, dynamic>>({
      'phone': digits,
      'verifiedMethod': verifiedMethod,
      'deviceFingerprintHash': hash,
      'fingerprint': Map<String, String>.from(snapshot.components),
      if (adminCode != null && adminCode.isNotEmpty) 'adminCode': adminCode,
    });
  }

  /// `users/{uid}.security.deviceTrustMode == limited` (24s peer-transfer).
  Future<bool> isDeviceTrustLimited(String phone) async {
    final uid = canonicalPhoneId(phone);
    if (uid.length < 12) return false;
    final snap = await _db.collection('users').doc(uid).get();
    if (!snap.exists) return false;
    final sec = snap.data()?['security'];
    if (sec is! Map) return false;
    if ((sec['deviceTrustMode'] ?? '').toString() != 'limited') return false;
    final until = sec['deviceTrustUntil'];
    if (until is Timestamp) {
      return until.toDate().isAfter(DateTime.now());
    }
    return true;
  }

  Stream<bool> watchDeviceTrustLimited(String phone) {
    final uid = canonicalPhoneId(phone);
    if (uid.length < 12) {
      return Stream<bool>.value(false);
    }
    return _db.collection('users').doc(uid).snapshots().map((snap) {
      if (!snap.exists) return false;
      final sec = snap.data()?['security'];
      if (sec is! Map) return false;
      if ((sec['deviceTrustMode'] ?? '').toString() != 'limited') return false;
      final until = sec['deviceTrustUntil'];
      if (until is Timestamp) {
        return until.toDate().isAfter(DateTime.now());
      }
      return true;
    });
  }

  DeviceBindingCheckResult _parseCheckResult(Map<String, dynamic> data) {
    final statusRaw = (data['status'] ?? '').toString();
    final status = switch (statusRaw) {
      'trusted_device' => DeviceBindingStatus.trustedDevice,
      'needs_verification' => DeviceBindingStatus.needsVerification,
      'device_bound_other_phone' => DeviceBindingStatus.deviceBoundOtherPhone,
      'phone_bound_other_device' => DeviceBindingStatus.phoneBoundOtherDevice,
      'blocked' => DeviceBindingStatus.blocked,
      _ => DeviceBindingStatus.unknown,
    };
    return DeviceBindingCheckResult(
      status: status,
      customToken: data['customToken'] as String?,
      message: data['message'] as String?,
      failedAttempts: (data['failedAttempts'] as num?)?.toInt() ?? 0,
      selfServeAvailable: data['selfServeAvailable'] == true,
      oldDeviceLabel: (data['oldDeviceLabel'] ?? '').toString(),
      selfServeHint: (data['selfServeHint'] ?? '').toString(),
      retryAfterMs: (data['retryAfterMs'] as num?)?.toInt() ?? 0,
    );
  }
}
