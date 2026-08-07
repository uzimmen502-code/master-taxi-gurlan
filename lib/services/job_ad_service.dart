import 'package:cloud_functions/cloud_functions.dart';

/// Иш топ — CF-only яратиш / шикоят.
class JobAdService {
  JobAdService._();

  static final FirebaseFunctions _fn = FirebaseFunctions.instance;

  static Future<({String adId, String status})> submitAd({
    required String type,
    required String text,
    required String authorName,
    String title = '',
    String priceText = '',
    String address = '',
    bool isUrgent = false,
  }) async {
    final res = await _fn.httpsCallable('submitJobAd').call({
      'type': type,
      'text': text,
      'title': title,
      'authorName': authorName,
      if (priceText.isNotEmpty) 'priceText': priceText,
      if (address.isNotEmpty) 'address': address,
      'isUrgent': isUrgent,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    return (
      adId: (data['adId'] ?? '') as String,
      status: (data['status'] ?? '') as String,
    );
  }

  static Future<String> submitComplaint({
    required String adId,
    required String reason,
  }) async {
    final res = await _fn.httpsCallable('submitJobComplaint').call({
      'adId': adId,
      'reason': reason,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    return (data['complaintId'] ?? '') as String;
  }
}
