import 'package:cloud_functions/cloud_functions.dart';

/// Agro qabul (sut va h.k.) Cloud Functions wrapper.
class AgroPickupService {
  AgroPickupService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<String> placeMilkOrder({
    required double literCount,
    required String pickupAddress,
    double? pickupLat,
    double? pickupLng,
    String note = '',
  }) async {
    final result = await _functions.httpsCallable('placeAgroPickupOrder').call({
      'productType': 'milk',
      'literCount': literCount,
      'pickupAddress': pickupAddress.trim(),
      if (pickupLat != null) 'pickupLat': pickupLat,
      if (pickupLng != null) 'pickupLng': pickupLng,
      'note': note.trim(),
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final id = (data['orderId'] ?? '') as String;
    if (id.isEmpty) {
      throw Exception('orderId missing');
    }
    return id;
  }

  Future<void> adminSetStatus({
    required String adminPhone,
    required String orderId,
    required String status,
    int? finalPrice,
  }) async {
    await _functions.httpsCallable('adminSetAgroPickupStatus').call({
      'adminPhone': adminPhone,
      'orderId': orderId,
      'status': status,
      if (finalPrice != null) 'finalPrice': finalPrice,
    });
  }

  Future<void> courierClaimPickup({
    required String courierPhone,
    required String orderId,
  }) async {
    await _functions.httpsCallable('courierClaimAgroPickup').call({
      'courierPhone': courierPhone,
      'orderId': orderId,
    });
  }

  Future<void> courierMarkArrived({
    required String courierPhone,
    required String orderId,
  }) async {
    await _functions.httpsCallable('courierMarkAgroPickupArrived').call({
      'courierPhone': courierPhone,
      'orderId': orderId,
    });
  }

  Future<void> courierMarkPickedUp({
    required String courierPhone,
    required String orderId,
  }) async {
    await _functions.httpsCallable('courierMarkAgroPickedUp').call({
      'courierPhone': courierPhone,
      'orderId': orderId,
    });
  }
}
