import 'package:cloud_functions/cloud_functions.dart';

/// Marshrut yo'nalish narxi — Cloud Functions orqali (server avtoritet).
///
/// `seedRoutePrice` — haydovchi onlayn bo'lganda: yo'nalishda narx yo'q bo'lsa
/// belgilaydi (bir marta), bor bo'lsa o'z reysiga ko'zgu qiladi. `setByAdmin` —
/// faqat admin/finance tahrir qiladi va faol reyslarga tarqatadi.
class MarshrutPricingService {
  MarshrutPricingService._();

  static final FirebaseFunctions _fn = FirebaseFunctions.instance;

  /// Qaytaradi: { ok, price, seeded, routeKey }
  static Future<Map<String, dynamic>> seedRoutePrice({
    required String scheduleId,
    required int price,
  }) async {
    final callable = _fn.httpsCallable('seedMarshrutRoutePrice');
    final res = await callable.call(<String, dynamic>{
      'scheduleId': scheduleId,
      'price': price,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Admin/finance — yo'nalish narxini tahrirlash. { ok, routeKey, price, propagated }
  static Future<Map<String, dynamic>> setByAdmin({
    required String from,
    required String to,
    required int price,
  }) async {
    final callable = _fn.httpsCallable('adminSetMarshrutRoutePrice');
    final res = await callable.call(<String, dynamic>{
      'from': from,
      'to': to,
      'price': price,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }
}
