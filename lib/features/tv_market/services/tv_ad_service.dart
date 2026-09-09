import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// «Реклама ва Эълонлар» — 5 тариф × 3 муддат. Wallet debit `publishTvAd`
/// CF ичида (client bonusBalance'ни тўғридан-тўғри ёза олмайди).
class TvAdService {
  TvAdService._();

  static final FirebaseFunctions _fn = FirebaseFunctions.instance;

  static Future<Map<String, dynamic>> publishTvAd({
    required String idempotencyKey,
    required String videoUrl,
    required String posterUrl,
    required String title,
    required int price,
    required String districtId,
    required String districtLabel,
    required String ownerName,
    required String description,
    required int durationDays,
    required String tier,
    bool showPhone = true,
    List<String> searchTokens = const [],
  }) async {
    final callable = _fn.httpsCallable('publishTvAd');
    final result = await callable.call(<String, dynamic>{
      'idempotencyKey': idempotencyKey,
      'videoUrl': videoUrl,
      'posterUrl': posterUrl,
      'title': title,
      'price': price,
      'districtId': districtId,
      'districtLabel': districtLabel,
      'ownerName': ownerName,
      'description': description,
      'durationDays': durationDays,
      'tier': tier,
      'showPhone': showPhone,
      if (searchTokens.isNotEmpty) 'searchTokens': searchTokens,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Мавжуд эълонни узайтириш — видеони қайта юклаш шарт эмас.
  /// Ҳали тугамаган муддат устига қўшилади, тугаган бўлса ҳозирдан
  /// бошланади (CF `renewTvAd`).
  static Future<Map<String, dynamic>> renewTvAd({
    required String idempotencyKey,
    required String clipId,
    required int durationDays,
    required String tier,
  }) async {
    final callable = _fn.httpsCallable('renewTvAd');
    final result = await callable.call(<String, dynamic>{
      'idempotencyKey': idempotencyKey,
      'clipId': clipId,
      'durationDays': durationDays,
      'tier': tier,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// `settings/app.tvAdPricing` (админ панелдан таҳрирланади) → тариф×муддат
  /// нархлари. Ҳужжат бўлмаса/бузуқ бўлса [tvAdTierPricingDefault] қайтади.
  static Future<Map<String, Map<int, int>>> loadPricing() async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('settings').doc('app').get();
      final raw = snap.data()?['tvAdPricing'];
      if (raw is Map) {
        final parsed = <String, Map<int, int>>{};
        for (final tierEntry in raw.entries) {
          final tierMap = tierEntry.value;
          if (tierMap is! Map) continue;
          final durations = <int, int>{};
          for (final e in tierMap.entries) {
            final k = int.tryParse('${e.key}');
            final v = (e.value as num?)?.toInt();
            if (k != null && v != null) durations[k] = v;
          }
          if (durations.isNotEmpty) parsed['${tierEntry.key}'] = durations;
        }
        if (parsed.isNotEmpty) return parsed;
      }
    } catch (e) {
      debugPrint('[TvAdService] loadPricing $e');
    }
    return {for (final e in tvAdTierPricingDefault.entries) e.key: Map.of(e.value)};
  }
}

/// AVA TV реклама тарифлари: тариф id → l10n калит суффикси.
/// Тартиб UI'да ҳам шу кетма-кетликда кўринади (жадвалдаги каби).
const tvAdTiers = ['basic', 'visibility', 'home', 'premium', 'pro_max'];

const tvAdDurationOptions = [7, 15, 30];

/// `settings/app.tvAdPricing` билан бир хил шакл — CF'даги placeholder
/// нархлар (admin панелдан ўзгартирилмагунча шу қийматлар кўринади).
const tvAdTierPricingDefault = <String, Map<int, int>>{
  'basic': {7: 20000, 15: 30000, 30: 50000},
  'visibility': {7: 30000, 15: 50000, 30: 75000},
  'home': {7: 50000, 15: 75000, 30: 100000},
  'premium': {7: 75000, 15: 100000, 30: 175000},
  'pro_max': {7: 100000, 15: 150000, 30: 250000},
};
