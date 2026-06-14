import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

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
  });

  final DeviceBindingStatus status;
  final String? customToken;
  final String? message;
  final int failedAttempts;

  bool get skipSms => status == DeviceBindingStatus.trustedDevice;
}

class DeviceBindingRepository {
  DeviceBindingRepository({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
  })  : _functions = functions ?? FirebaseFunctions.instance,
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

  Future<DeviceBindingCheckResult> checkDeviceBinding({
    required String phone,
    required DeviceFingerprintSnapshot snapshot,
  }) async {
    final hash = normalizeFingerprintHash(snapshot.hash);
    if (!isValidFingerprintHash(hash)) {
      throw StateError('deviceFingerprintHash noto\'g\'ri');
    }

    final callable = _functions.httpsCallable('checkDeviceBinding');
    final digits = phoneDigits(phone);
    final result = await callable.call<Map<String, dynamic>>({
      'phone': digits,
      'deviceFingerprintHash': hash,
      'fingerprint': Map<String, String>.from(snapshot.components),
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return _parseCheckResult(data);
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

    final callable = _functions.httpsCallable('registerDeviceBinding');
    final digits = phoneDigits(phone);
    await callable.call<Map<String, dynamic>>({
      'phone': digits,
      'verifiedMethod': verifiedMethod,
      'deviceFingerprintHash': hash,
      'fingerprint': Map<String, String>.from(snapshot.components),
      if (adminCode != null && adminCode.isNotEmpty) 'adminCode': adminCode,
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
    );
  }
}
