import 'package:cloud_functions/cloud_functions.dart';

/// Кошелёк (қайтим, сут кредити) — Cloud Functions орқали.
class BalanceService {
  BalanceService._();

  static final FirebaseFunctions _fn = FirebaseFunctions.instance;

  static String idempotencyKey(String seed) {
    final t = DateTime.now().microsecondsSinceEpoch;
    return '${t}_${seed.hashCode}_$t';
  }

  static Future<Map<String, dynamic>> creditChange({
    required String userPhone,
    required int orderTotal,
    required int cashPaid,
    required String refType,
    required String refId,
    required String module,
    required String idempotencyKey,
    String? operatorPhone,
  }) async {
    final callable = _fn.httpsCallable('creditChange');
    final result = await callable.call(<String, dynamic>{
      'userPhone': userPhone,
      'orderTotal': orderTotal,
      'cashPaid': cashPaid,
      'refType': refType,
      'refId': refId,
      'module': module,
      'idempotencyKey': idempotencyKey,
      if (operatorPhone != null && operatorPhone.isNotEmpty)
        'operatorPhone': operatorPhone,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Битта CF: `orders` + омбор + кашелёк + ledger + нақд қайтим (атомик).
  static Future<Map<String, dynamic>> placeOrderWithWallet({
    required String userPhone,
    required String idempotencyKey,
    required Map<String, dynamic> orderBase,
    required List<Map<String, dynamic>> decrements,
  }) async {
    final callable = _fn.httpsCallable('placeOrderWithWallet');
    final result = await callable.call(<String, dynamic>{
      'userPhone': userPhone,
      'idempotencyKey': idempotencyKey,
      'orderBase': orderBase,
      'decrements': decrements,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  static Future<Map<String, dynamic>> debitForOrder({
    required String userPhone,
    required int amount,
    required String refType,
    required String refId,
    required String module,
    required String idempotencyKey,
  }) async {
    final callable = _fn.httpsCallable('debitForOrder');
    final result = await callable.call(<String, dynamic>{
      'userPhone': userPhone,
      'amount': amount,
      'refType': refType,
      'refId': refId,
      'module': module,
      'idempotencyKey': idempotencyKey,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  static Future<Map<String, dynamic>> creditSupplier({
    required String adminPhone,
    required String userPhone,
    required int amount,
    required String note,
    required String dateKey,
    String module = 'milk',
  }) async {
    final callable = _fn.httpsCallable('creditSupplier');
    final result = await callable.call(<String, dynamic>{
      'adminPhone': adminPhone,
      'userPhone': userPhone,
      'amount': amount,
      'note': note,
      'dateKey': dateKey,
      'module': module,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  static Future<Map<String, dynamic>> requestPayout({
    required String userPhone,
    required int amount,
    required String idempotencyKey,
  }) async {
    final callable = _fn.httpsCallable('requestPayout');
    final result = await callable.call(<String, dynamic>{
      'userPhone': userPhone,
      'amount': amount,
      'idempotencyKey': idempotencyKey,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  static Future<Map<String, dynamic>> confirmPayout({
    required String adminPhone,
    required String requestId,
  }) async {
    final callable = _fn.httpsCallable('confirmPayout');
    final result = await callable.call(<String, dynamic>{
      'adminPhone': adminPhone,
      'requestId': requestId,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  static Future<Map<String, dynamic>> rejectPayout({
    required String adminPhone,
    required String requestId,
  }) async {
    final callable = _fn.httpsCallable('rejectPayout');
    final result = await callable.call(<String, dynamic>{
      'adminPhone': adminPhone,
      'requestId': requestId,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }
}
