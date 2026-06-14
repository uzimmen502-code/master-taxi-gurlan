import 'package:cloud_functions/cloud_functions.dart';

/// Кошелёк (қайтим, сут кредити) — Cloud Functions орқали.
class BalanceService {
  BalanceService._();

  static final FirebaseFunctions _fn = FirebaseFunctions.instance;

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

  /// Birthday bonus — admin Phone Auth + `grantBirthdayBonus` CF.
  static Future<Map<String, dynamic>> grantBirthdayBonus({
    required String uid,
    required int year,
    required int amount,
    String operatorPhone = '',
  }) async {
    final callable = _fn.httpsCallable('grantBirthdayBonus');
    final result = await callable.call(<String, dynamic>{
      'uid': uid,
      'year': year,
      'amount': amount,
      if (operatorPhone.isNotEmpty) 'operatorPhone': operatorPhone,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }
}
