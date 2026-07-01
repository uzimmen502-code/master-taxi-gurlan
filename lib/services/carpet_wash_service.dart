import 'package:cloud_functions/cloud_functions.dart';

/// Gilam yuvish Cloud Functions wrapper.
class CarpetWashService {
  CarpetWashService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<String> placeOrder({
    required int carpetCount,
    required String pickupAddress,
    double? pickupLat,
    double? pickupLng,
    String note = '',
  }) async {
    final result = await _functions.httpsCallable('placeCarpetWashOrder').call({
      'carpetCount': carpetCount,
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
    await _functions.httpsCallable('adminSetCarpetWashStatus').call({
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
    await _functions.httpsCallable('courierClaimCarpetPickup').call({
      'courierPhone': courierPhone,
      'orderId': orderId,
    });
  }

  Future<void> courierMarkPickedUp({
    required String courierPhone,
    required String orderId,
  }) async {
    await _functions.httpsCallable('courierMarkCarpetPickedUp').call({
      'courierPhone': courierPhone,
      'orderId': orderId,
    });
  }

  Future<void> courierMarkArrived({
    required String courierPhone,
    required String orderId,
    required String leg,
  }) async {
    await _functions.httpsCallable('courierMarkCarpetArrived').call({
      'courierPhone': courierPhone,
      'orderId': orderId,
      'leg': leg,
    });
  }

  Future<void> courierClaimReturn({
    required String courierPhone,
    required String orderId,
  }) async {
    await _functions.httpsCallable('courierClaimCarpetReturn').call({
      'courierPhone': courierPhone,
      'orderId': orderId,
    });
  }

  Future<void> courierMarkDelivered({
    required String courierPhone,
    required String orderId,
  }) async {
    await _functions.httpsCallable('courierMarkCarpetDelivered').call({
      'courierPhone': courierPhone,
      'orderId': orderId,
    });
  }
}
