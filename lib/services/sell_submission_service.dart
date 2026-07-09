import 'package:cloud_functions/cloud_functions.dart';

/// `sell_submissions` — CF-only yaratish.
class SellSubmissionService {
  SellSubmissionService._();

  static final FirebaseFunctions _fn = FirebaseFunctions.instance;

  static Future<String> submit({
    required List<Map<String, dynamic>> items,
    required String userName,
    String pickupAddress = '',
    double? pickupLat,
    double? pickupLng,
    String pickupNote = '',
    Map<String, dynamic>? pickupDetails,
  }) async {
    final res = await _fn.httpsCallable('submitSellSubmission').call({
      'items': items,
      'userName': userName,
      if (pickupAddress.isNotEmpty) 'pickupAddress': pickupAddress,
      if (pickupLat != null) 'pickupLat': pickupLat,
      if (pickupLng != null) 'pickupLng': pickupLng,
      if (pickupNote.isNotEmpty) 'pickupNote': pickupNote,
      if (pickupDetails != null) 'pickupDetails': pickupDetails,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    return (data['submissionId'] ?? '') as String;
  }
}
