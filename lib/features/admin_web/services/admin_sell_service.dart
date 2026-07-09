import 'package:cloud_functions/cloud_functions.dart';

/// Admin — `sell_submissions` (CF-only yozuvlar).
class AdminSellService {
  AdminSellService._();

  static final FirebaseFunctions _fn = FirebaseFunctions.instance;

  static Future<void> updateStatus({
    required String adminPhone,
    required String submissionId,
    required String status,
    String? adminNote,
  }) async {
    await _fn.httpsCallable('adminUpdateSellSubmission').call({
      'adminPhone': adminPhone,
      'submissionId': submissionId,
      'action': 'setStatus',
      'status': status,
      if (adminNote != null) 'adminNote': adminNote,
    });
  }

  static Future<void> forward({
    required String adminPhone,
    required String submissionId,
    required String forwardAudience,
    List<String> targetUserIds = const [],
    String adminNote = '',
  }) async {
    await _fn.httpsCallable('adminUpdateSellSubmission').call({
      'adminPhone': adminPhone,
      'submissionId': submissionId,
      'action': 'forward',
      'forwardAudience': forwardAudience,
      'targetUserIds': targetUserIds,
      if (adminNote.isNotEmpty) 'adminNote': adminNote,
    });
  }
}
