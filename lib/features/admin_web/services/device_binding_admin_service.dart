import 'package:cloud_functions/cloud_functions.dart';

/// Yangi composite device binding — admin tasdiqlash (Cloud Functions).
class DeviceBindingAdminService {
  DeviceBindingAdminService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<String?> setAutoApprove({
    required String adminPhone,
    required bool enabled,
  }) async {
    try {
      final fn =
          _functions.httpsCallable('adminSetDeviceBindingAutoApprove');
      await fn.call(<String, dynamic>{
        'adminPhone': adminPhone,
        'enabled': enabled,
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return 'Xatolik: $e';
    }
  }

  Future<String?> autoApprove({
    required String adminPhone,
    required String deviceFingerprintHash,
    String? phone,
  }) async {
    try {
      final fn = _functions.httpsCallable('adminAutoApproveDeviceBinding');
      await fn.call(<String, dynamic>{
        'adminPhone': adminPhone,
        'deviceFingerprintHash': deviceFingerprintHash,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return 'Xatolik: $e';
    }
  }

  Future<String?> manualApprove({
    required String adminPhone,
    required String deviceFingerprintHash,
    required String phone,
  }) async {
    try {
      final fn = _functions.httpsCallable('adminManualApproveDeviceBinding');
      await fn.call(<String, dynamic>{
        'adminPhone': adminPhone,
        'deviceFingerprintHash': deviceFingerprintHash,
        'phone': phone,
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return 'Xatolik: $e';
    }
  }

  Future<String?> unblock({
    required String adminPhone,
    required String deviceFingerprintHash,
  }) async {
    try {
      final fn = _functions.httpsCallable('adminUnblockDeviceBinding');
      await fn.call(<String, dynamic>{
        'adminPhone': adminPhone,
        'deviceFingerprintHash': deviceFingerprintHash,
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return 'Xatolik: $e';
    }
  }

  Future<String?> reject({
    required String adminPhone,
    required String deviceFingerprintHash,
  }) async {
    try {
      final fn = _functions.httpsCallable('adminRejectDeviceBinding');
      await fn.call(<String, dynamic>{
        'adminPhone': adminPhone,
        'deviceFingerprintHash': deviceFingerprintHash,
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return 'Xatolik: $e';
    }
  }
}
