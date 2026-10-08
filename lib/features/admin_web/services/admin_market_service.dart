import 'package:cloud_functions/cloud_functions.dart';

import '../../ads/models/ad_model.dart';

/// `adminListMarketAds` жавобининг бир саҳифаси.
class MarketAdsPage {
  const MarketAdsPage({required this.ads, this.nextCursor});

  final List<AdModel> ads;

  /// Кейинги саҳифа учун — серверга ўзгармасдан қайтарилади.
  /// `null` — бошқа саҳифа йўқ (ёки сервер ҳали саҳифаламайди).
  final Map<String, dynamic>? nextCursor;
}

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

  /// `settings/app.marketAutoApprove` — янги/қайта юборилган эълонлар дарҳол active.
  Future<void> setAutoApprove({
    required String adminPhone,
    required bool enabled,
  }) async {
    await _call('adminSetMarketAutoApprove', {
      'adminPhone': adminPhone,
      'enabled': enabled,
    });
  }

  /// `settings/app.platformFeaturedAuto` — Тавсия этамиз витринаси АВТО/ҚЎЛДА.
  Future<void> setPlatformFeaturedAuto({
    required String adminPhone,
    required bool enabled,
  }) async {
    await _call('adminSetPlatformFeaturedAuto', {
      'adminPhone': adminPhone,
      'enabled': enabled,
    });
  }

  /// `settings/app.platformDeliveryFeePercent` — етказиб бериш ҳақи %.
  Future<void> setPlatformDeliveryFeePercent({
    required String adminPhone,
    required double percent,
  }) async {
    await _call('adminSetPlatformDeliveryFeePercent', {
      'adminPhone': adminPhone,
      'percent': percent,
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

  /// Bozor shikoyatini (`reports`, `type: market_ad`) hal qilish.
  /// `adminResolveDatingReport` CF aslida umumiy — istalgan `reports`
  /// hujjatini `resolved` qiladi (assertAdmin); yangi CF deploy shart emas.
  Future<void> resolveComplaint({
    required String adminPhone,
    required String reportId,
  }) async {
    await _call('adminResolveDatingReport', {
      'adminPhone': adminPhone,
      'reportId': reportId,
    });
  }

  /// Бир саҳифа (сервер: энг янгиси биринчи, 500 та). [after] — олдинги
  /// саҳифанинг [MarketAdsPage.nextCursor]и, `null` — биринчи саҳифа.
  Future<MarketAdsPage> listAdsPage({
    required String adminPhone,
    Map<String, dynamic>? after,
  }) async {
    try {
      final result =
          await _functions.httpsCallable('adminListMarketAds').call({
        'adminPhone': adminPhone,
        if (after != null) 'after': after,
      });
      final raw = result.data;
      final list = (raw is Map ? raw['ads'] : null) as List<dynamic>? ?? [];
      final next = raw is Map ? raw['nextCursor'] : null;
      return MarketAdsPage(
        ads: list
            .map((e) {
              final map = Map<String, dynamic>.from(e as Map);
              return AdModel.fromMap(map['id'] as String? ?? '', map);
            })
            .where((a) => a.id.isNotEmpty)
            .toList(growable: false),
        nextCursor: next is Map ? Map<String, dynamic>.from(next) : null,
      );
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
