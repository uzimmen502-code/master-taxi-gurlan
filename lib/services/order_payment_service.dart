import 'package:cloud_functions/cloud_functions.dart';

/// Post-paid буюртма + курьер тўлови (Cloud Functions).
class OrderPaymentService {
  OrderPaymentService._();

  static final FirebaseFunctions _fn = FirebaseFunctions.instance;

  static Future<Map<String, dynamic>> placeOrderPostPaid({
    required String userPhone,
    required String idempotencyKey,
    required Map<String, dynamic> orderBase,
    required List<Map<String, dynamic>> decrements,
  }) async {
    final result = await _fn.httpsCallable('placeOrderPostPaid').call({
      'userPhone': userPhone,
      'idempotencyKey': idempotencyKey,
      'orderBase': orderBase,
      'decrements': decrements,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Мижоз: эрта ҳолатдаги food/bread буюртмани бекор (+ захира/ҳамён).
  static Future<Map<String, dynamic>> customerCancelOrder({
    required String orderId,
    String reason = '',
  }) async {
    final result = await _fn.httpsCallable('customerCancelOrder').call({
      'orderId': orderId,
      if (reason.isNotEmpty) 'reason': reason,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  static Future<void> courierMarkPicked({
    required String orderId,
    required String courierPhone,
    double? lat,
    double? lng,
  }) async {
    await _fn.httpsCallable('courierMarkPicked').call({
      'orderId': orderId,
      'courierPhone': courierPhone,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    });
  }

  static Future<void> courierMarkArrived({
    required String orderId,
    required String courierPhone,
    double? lat,
    double? lng,
  }) async {
    await _fn.httpsCallable('courierMarkArrived').call({
      'orderId': orderId,
      'courierPhone': courierPhone,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    });
  }

  static Future<int?> getCustomerWalletBalance({
    required String courierPhone,
    required String customerPhone,
  }) async {
    try {
      final result =
          await _fn.httpsCallable('courierGetCustomerWalletBalance').call({
        'courierPhone': courierPhone,
        'customerPhone': customerPhone,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return (data['bonusBalance'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> courierSubmitPayment({
    required String orderId,
    required String courierPhone,
    required List<Map<String, dynamic>> lines,
    double? lat,
    double? lng,
  }) async {
    final result = await _fn.httpsCallable('courierSubmitPayment').call({
      'orderId': orderId,
      'courierPhone': courierPhone,
      'lines': lines,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }
}
