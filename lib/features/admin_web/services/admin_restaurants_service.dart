// Админ — кафе-ресторан callable'лари (default codebase, us-central1).
// Ҳамма ёзув СЕРВЕРДА (audit, версия, idempotency); экран фақат ўқийди ва
// чақиради. Хато — `AdminOrdersService` каби матн (`null` = муваффақият).

import 'package:cloud_functions/cloud_functions.dart';

class AdminRestaurantsException implements Exception {
  const AdminRestaurantsException(this.code, this.reason, this.message);

  final String code;

  /// Сервер `details.code` (`PRICE_INVALID`, `ORDER_ALREADY_FINAL`, …).
  final String reason;
  final String message;

  @override
  String toString() => reason.isNotEmpty ? '$reason ($message)' : message;
}

class AdminRestaurantsService {
  AdminRestaurantsService({FirebaseFunctions? functions}) : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    try {
      final res = await _functions.httpsCallable(name).call<dynamic>(data);
      final raw = res.data;
      return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      final details = e.details is Map ? Map<String, dynamic>.from(e.details as Map) : null;
      final reason = (details?['code'] ?? '').toString();
      throw AdminRestaurantsException(e.code, reason, e.message ?? e.code);
    }
  }

  /// `applied → approved|rejected`, `approved → suspended|closed`, … (сервер жадвали).
  Future<void> setStatus(String restaurantId, String status, {String reason = ''}) =>
      _call('adminSetRestaurantStatus', {'restaurantId': restaurantId, 'status': status, 'reason': reason});

  /// Янги версия рақамини қайтаради.
  Future<int> setDeliveryPrices(Map<String, dynamic> payload) async =>
      ((await _call('adminSetRestaurantDeliveryPrices', payload))['version'] as num?)?.toInt() ?? 0;

  Future<void> setAutoApprove(bool enabled) => _call('adminSetRestaurantAutoApprove', {'enabled': enabled});

  Future<List<String>> setStage({required String stage, required List<String> testerIds}) async {
    final r = await _call('adminSetRestaurantsStage', {'stage': stage, 'testerIds': testerIds});
    return ((r['testerIds'] as List?) ?? const []).map((e) => e.toString()).toList();
  }

  /// Қайтарилган 2 % (сўм) — хабар учун.
  Future<int> cancelOrder(String orderId, {String reason = ''}) async =>
      ((await _call('adminCancelRestaurantOrder', {'orderId': orderId, 'reason': reason}))['refundAmount'] as num?)?.toInt() ?? 0;
}
