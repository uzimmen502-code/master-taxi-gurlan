import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Mahalliy taksi to'lovi — hamyon intent + safar yakunlash (CF).
class LocalTaxiPaymentService {
  LocalTaxiPaymentService._();

  static final _fn = FirebaseFunctions.instance;
  static final _trips = FirebaseFirestore.instance.collection('trips');

  /// Yo'lovchi hamyondan qancha ishlatishini belgilaydi (0 = faqat naqd).
  static Future<void> setPassengerWalletIntent({
    required String tripId,
    required int amount,
  }) async {
    if (tripId.isEmpty) return;
    final safe = amount < 0 ? 0 : amount;
    await _trips.doc(tripId).update({
      'passengerWalletIntent': safe,
      'passengerWalletUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Haydovchi safarni yakunlaydi; server hamyon yechimi + trip completed.
  static Future<LocalTripCompleteResult> completeTrip({
    required String tripId,
    required int fare,
    required int cashPaid,
  }) async {
    final callable = _fn.httpsCallable('completeLocalTrip');
    final res = await callable.call(<String, dynamic>{
      'tripId': tripId,
      'fare': fare,
      'cashPaid': cashPaid,
    });
    final map = Map<String, dynamic>.from(res.data as Map);
    return LocalTripCompleteResult(
      fare: (map['fare'] as num?)?.toInt() ?? fare,
      cashPaid: (map['cashPaid'] as num?)?.toInt() ?? cashPaid,
      walletPaid: (map['walletPaid'] as num?)?.toInt() ?? 0,
      cashDue: (map['cashDue'] as num?)?.toInt() ?? 0,
      change: (map['change'] as num?)?.toInt() ?? 0,
    );
  }
}

class LocalTripCompleteResult {
  const LocalTripCompleteResult({
    required this.fare,
    required this.cashPaid,
    required this.walletPaid,
    required this.cashDue,
    required this.change,
  });

  final int fare;
  final int cashPaid;
  final int walletPaid;
  final int cashDue;
  final int change;
}
