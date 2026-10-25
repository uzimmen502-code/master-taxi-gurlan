import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Харидор дўкон ёки маҳсулот экранини очганини серверга билдиради (`recordShopEvent`, 6-босқич). Санашни сервер
/// қилади (бир харидор × бир объект × бир кун = 1; эгасининг ўзи саналмайди) — бу ер фақат «жим» хабар:
/// хато ёки логинсизлик харидорга ҳеч қачон кўрсатилмайди. Бир сессияда бир объект бир марта юборилади
/// (керакмас чақирувлар бўлмасин).
///
/// Манбалар: market | video | map | link | qr | search | shop | product | other (сервер рўйхати билан бир хил).
class ShopStatsRecorder {
  ShopStatsRecorder._();

  static const sources = ['market', 'video', 'map', 'link', 'qr', 'search', 'shop', 'product', 'other'];

  static final Set<String> _sent = {};

  /// Тест учун алмаштирилади (Firebase'сиз). `null` — ҳақиқий callable.
  @visibleForTesting
  static Future<void> Function(Map<String, Object?> data)? sink;

  @visibleForTesting
  static void resetForTest() => _sent.clear();

  static void shopView({required String ownerPhone, String businessId = '', String source = 'other'}) =>
      _send({'kind': 'shop_view', 'ownerPhone': ownerPhone, if (businessId.isNotEmpty) 'businessId': businessId, 'source': source});

  static void productView({required String ownerPhone, required String itemId, String source = 'other'}) =>
      _send({'kind': 'product_view', 'ownerPhone': ownerPhone, 'itemId': itemId, 'source': source});

  static void _send(Map<String, Object?> data) {
    final key = '${data['kind']}|${data['ownerPhone']}|${data['businessId'] ?? ''}|${data['itemId'] ?? ''}';
    if (!_sent.add(key)) return;
    final payload = {...data, 'source': sources.contains(data['source']) ? data['source'] : 'other'};
    final custom = sink;
    Future<void> run() async {
      if (custom != null) return custom(payload);
      await FirebaseFunctions.instance.httpsCallable('recordShopEvent').call<Object?>(payload);
    }

    run().catchError((Object e) => debugPrint('[ShopStats] $e'));
  }
}
