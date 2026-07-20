import 'package:cloud_functions/cloud_functions.dart';

/// Иш топ — CF-only яратиш / шикоят.
class JobAdService {
  JobAdService._();

  static final FirebaseFunctions _fn = FirebaseFunctions.instance;

  static Future<String> submitAd({
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
      'authorName': authorName,
      if (title.isNotEmpty) 'title': title,
      if (priceText.isNotEmpty) 'priceText': priceText,
      if (address.isNotEmpty) 'address': address,
      'isUrgent': isUrgent,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    return (data['adId'] ?? '') as String;
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
