import 'package:cloud_functions/cloud_functions.dart';

import '../../ads/models/ad_model.dart';

/// Admin web — Onlayn BOZOR e'lonlari (Cloud Functions).
class AdminMarketService {
  AdminMarketService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<void> deleteAd({
    required String adminPhone,
    required String adId,
  }) async {
    await _call('adminDeleteMarketAd', {
      'adminPhone': adminPhone,
      'adId': adId,
    });
  }

  Future<void> updateAdStatus({
    required String adminPhone,
    required String adId,
    required String status,
  }) async {
    await _call('adminUpdateMarketAdStatus', {
      'adminPhone': adminPhone,
      'adId': adId,
      'status': status,
    });
  }

  Future<void> updateAd({
    required String adminPhone,
    required String adId,
    required String title,
    required String description,
    required int price,
    required String phone,
    required String sellerName,
    String? status,
    String? adminNote,
  }) async {
    await _call('adminUpdateMarketAd', {
      'adminPhone': adminPhone,
      'adId': adId,
      'title': title,
      'description': description,
      'price': price,
      'phone': phone,
      'sellerName': sellerName,
      if (status != null) 'status': status,
      if (adminNote != null) 'adminNote': adminNote,
    });
  }

  Future<List<AdModel>> listAds({required String adminPhone}) async {
    try {
      final result =
          await _functions.httpsCallable('adminListMarketAds').call({
        'adminPhone': adminPhone,
      });
      final raw = result.data;
      final list = (raw is Map ? raw['ads'] : null) as List<dynamic>? ?? [];
      return list
          .map((e) {
            final map = Map<String, dynamic>.from(e as Map);
            return AdModel.fromMap(map['id'] as String? ?? '', map);
          })
          .where((a) => a.id.isNotEmpty)
          .toList(growable: false);
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? e.code);
    }
  }

  Future<void> _call(String name, Map<String, dynamic> data) async {
    try {
      await _functions.httpsCallable(name).call(data);
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? e.code);
    }
  }
}
