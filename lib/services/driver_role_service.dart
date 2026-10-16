import 'package:cloud_functions/cloud_functions.dart';

/// Haydovchi roli — server orqali chiqish va admin reset.
class DriverRoleService {
  DriverRoleService._();

  static final FirebaseFunctions _fn = FirebaseFunctions.instance;

  /// Admin: barcha taksi haydovchilar bazasini tozalash.
  static Future<Map<String, dynamic>> adminResetTaxiDriversRegistry({
    required String adminPhone,
  }) async {
    final callable = _fn.httpsCallable('adminResetTaxiDriversRegistry');
    final result = await callable.call(<String, dynamic>{
      'adminPhone': adminPhone,
      'confirmText': 'RESET_TAXI_DRIVERS',
    });
    final data = result.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{'ok': true};
  }
}
