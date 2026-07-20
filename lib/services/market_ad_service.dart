import 'package:cloud_functions/cloud_functions.dart';

/// Onlayn BOZOR — CF-only яратиш / шикоят.
class MarketAdService {
  MarketAdService._();

  static final FirebaseFunctions _fn = FirebaseFunctions.instance;

  static Future<String> submitAd({
    required String title,
    required String description,
    required int price,
    required String sellerName,
    required List<String> imageUrls,
  }) async {
    final res = await _fn.httpsCallable('submitMarketAd').call({
      'title': title,
      'description': description,
      'price': price,
      'sellerName': sellerName,
      'imageUrls': imageUrls,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    return (data['adId'] ?? '') as String;
  }

  static Future<String> submitComplaint({
    required String adId,
    required String reason,
  }) async {
    final res = await _fn.httpsCallable('submitMarketComplaint').call({
      'adId': adId,
      'reason': reason,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    return (data['reportId'] ?? '') as String;
  }
}
