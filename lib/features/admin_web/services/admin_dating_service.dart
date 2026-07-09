import 'package:cloud_functions/cloud_functions.dart';

/// Admin — dating `reports` hal qilish.
class AdminDatingService {
  AdminDatingService._();

  static final FirebaseFunctions _fn = FirebaseFunctions.instance;

  static Future<void> resolveReport({
    required String adminPhone,
    required String reportId,
  }) async {
    await _fn.httpsCallable('adminResolveDatingReport').call({
      'adminPhone': adminPhone,
      'reportId': reportId,
    });
  }
}
