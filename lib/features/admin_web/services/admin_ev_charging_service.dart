import 'package:cloud_functions/cloud_functions.dart';

/// Admin web — ⚡ EV zaryadlash nuqtalari moderatsiyasi (Cloud Functions,
/// `admin_jobs_service.dart` bilan bir xil naqsh — `assertAdmin()` server
/// tomonda tekshiradi, Firestore rules'ga tayanilmaydi).
class AdminEvChargingService {
  AdminEvChargingService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<void> resolveReport({
    required String adminPhone,
    required String stationId,
    required String reportId,
  }) {
    return _call('adminResolveEvReport', {
      'adminPhone': adminPhone,
      'stationId': stationId,
      'reportId': reportId,
    });
  }

  /// `working` | `partially_working` | `not_working` | `unknown`.
  Future<void> updateStationStatus({
    required String adminPhone,
    required String stationId,
    required String status,
  }) {
    return _call('adminUpdateEvStationStatus', {
      'adminPhone': adminPhone,
      'stationId': stationId,
      'status': status,
    });
  }

  Future<void> setStationActive({
    required String adminPhone,
    required String stationId,
    required bool isActive,
  }) {
    return _call('adminSetEvStationActive', {
      'adminPhone': adminPhone,
      'stationId': stationId,
      'isActive': isActive,
    });
  }

  Future<void> _call(String name, Map<String, dynamic> data) async {
    try {
      await _functions.httpsCallable(name).call(data);
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? e.code);
    }
  }
}
