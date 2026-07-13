import 'package:cloud_functions/cloud_functions.dart';

/// Sotuvchi mini-kassa — joyida sotuv (CF).
class SellerSaleService {
  SellerSaleService._();

  static final _fn = FirebaseFunctions.instance;

  static Future<SellerWalletLookup> getCustomerWalletBalance(
    String customerPhone,
  ) async {
    try {
      final res =
          await _fn.httpsCallable('sellerGetCustomerWalletBalance').call({
        'customerPhone': customerPhone,
      });
      final map = Map<String, dynamic>.from(res.data as Map);
      return SellerWalletLookup(
        ok: true,
        found: map['found'] == true,
        balance: (map['bonusBalance'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return const SellerWalletLookup(ok: false, found: false, balance: 0);
    }
  }

  static Future<SellerSaleResult> placeSale({
    required String idempotencyKey,
    required List<Map<String, dynamic>> items,
    required int cashPaid,
    required int walletPaid,
    String customerPhone = '',
  }) async {
    final res = await _fn.httpsCallable('sellerPlaceSale').call({
      'idempotencyKey': idempotencyKey,
      'items': items,
      'cashPaid': cashPaid,
      'walletPaid': walletPaid,
      if (customerPhone.trim().isNotEmpty) 'customerPhone': customerPhone.trim(),
    });
    final map = Map<String, dynamic>.from(res.data as Map);
    return SellerSaleResult(
      orderId: (map['orderId'] ?? '').toString(),
      total: (map['total'] as num?)?.toInt() ?? 0,
      cashPaid: (map['cashPaid'] as num?)?.toInt() ?? cashPaid,
      walletPaid: (map['walletPaid'] as num?)?.toInt() ?? walletPaid,
      changeCredit: (map['changeCredit'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<void> markPickupReady(String orderId) async {
    await _fn.httpsCallable('sellerMarkPickupReady').call({'orderId': orderId});
  }

  static Future<SellerSaleResult> submitPickupPayment({
    required String orderId,
    required int cashPaid,
    required int walletPaid,
  }) async {
    final res = await _fn.httpsCallable('sellerSubmitPickupPayment').call({
      'orderId': orderId,
      'cashPaid': cashPaid,
      'walletPaid': walletPaid,
    });
    final map = Map<String, dynamic>.from(res.data as Map);
    return SellerSaleResult(
      orderId: (map['orderId'] ?? orderId).toString(),
      total: (map['total'] as num?)?.toInt() ?? 0,
      cashPaid: (map['cashPaid'] as num?)?.toInt() ?? cashPaid,
      walletPaid: (map['walletPaid'] as num?)?.toInt() ?? walletPaid,
      changeCredit: (map['changeCredit'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<SellerShiftSummary> getShiftSummary({String? dateKey}) async {
    final res = await _fn.httpsCallable('sellerGetShiftSummary').call({
      if (dateKey != null && dateKey.isNotEmpty) 'dateKey': dateKey,
    });
    final map = Map<String, dynamic>.from(res.data as Map);
    return SellerShiftSummary(
      dateKey: (map['dateKey'] ?? '').toString(),
      count: (map['count'] as num?)?.toInt() ?? 0,
      total: (map['total'] as num?)?.toInt() ?? 0,
      cashPaid: (map['cashPaid'] as num?)?.toInt() ?? 0,
      walletPaid: (map['walletPaid'] as num?)?.toInt() ?? 0,
      changeCredit: (map['changeCredit'] as num?)?.toInt() ?? 0,
      posCount: (map['posCount'] as num?)?.toInt() ?? 0,
      pickupCount: (map['pickupCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class SellerWalletLookup {
  const SellerWalletLookup({
    required this.ok,
    required this.found,
    required this.balance,
  });

  final bool ok;
  final bool found;
  final int balance;
}

class SellerSaleResult {
  const SellerSaleResult({
    required this.orderId,
    required this.total,
    required this.cashPaid,
    required this.walletPaid,
    required this.changeCredit,
  });

  final String orderId;
  final int total;
  final int cashPaid;
  final int walletPaid;
  final int changeCredit;
}

class SellerShiftSummary {
  const SellerShiftSummary({
    required this.dateKey,
    required this.count,
    required this.total,
    required this.cashPaid,
    required this.walletPaid,
    required this.changeCredit,
    required this.posCount,
    required this.pickupCount,
  });

  final String dateKey;
  final int count;
  final int total;
  final int cashPaid;
  final int walletPaid;
  final int changeCredit;
  final int posCount;
  final int pickupCount;
}
