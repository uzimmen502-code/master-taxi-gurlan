import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

import '../models/carpet_wash_order.dart';

/// Gilam yuvish Cloud Functions wrapper.
class CarpetWashService {
  CarpetWashService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;
  static const _uuid = Uuid();

  /// `courierListCarpetTasks` рўйхатлари: олиш учун (`pickup_ready`,
  /// `return_ready`) ва курьернинг ўзи олган вазифалари.
  static const courierListPickup = 'pickup';
  static const courierListReturn = 'return';
  static const courierListActive = 'active';

  /// Курьер вазифалари (`courierListCarpetTasks`).
  ///
  /// `carpet_wash_orders` қоидаси курьерга рўйхат бермайди: қоида
  /// майдонларни кеса олмайди, сервер эса олишдан олдин ([courierListPickup],
  /// [courierListReturn]) ФАҚАТ id, гилам сони ва вақтни қайтаради — мижоз
  /// исми, телефони ва манзили вазифани олгандан кейин
  /// ([courierListActive]) очилади (40-қоида).
  Future<List<CarpetWashOrder>> listCourierTasks(String list) async {
    final result = await _functions
        .httpsCallable('courierListCarpetTasks')
        .call({'list': list});
    final data = Map<String, dynamic>.from(result.data as Map);
    final raw = (data['tasks'] as List?) ?? const [];
    final fallbackStatus = switch (list) {
      courierListPickup => CarpetWashOrder.statusPickupReady,
      courierListReturn => CarpetWashOrder.statusReturnReady,
      _ => '',
    };
    return [
      for (final m in raw.whereType<Map>())
        courierTaskFromMap(
          Map<String, dynamic>.from(m),
          fallbackStatus: fallbackStatus,
        ),
    ];
  }

  /// `courierListCarpetTasks` элементи → [CarpetWashOrder]. Олиш рўйхатида
  /// `status` ва мижоз майдонлари келмайди — улар бўш қолади.
  static CarpetWashOrder courierTaskFromMap(
    Map<String, dynamic> m, {
    String fallbackStatus = '',
  }) {
    DateTime? at(Object? ms) =>
        ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null;
    return CarpetWashOrder(
      id: (m['id'] ?? '') as String,
      customerId: '',
      customerPhone: (m['customerPhone'] ?? '') as String,
      customerName: (m['customerName'] ?? '') as String,
      pickupAddress: (m['pickupAddress'] ?? '') as String,
      carpetCount: (m['carpetCount'] as num?)?.toInt() ?? 0,
      status: (m['status'] as String?) ?? fallbackStatus,
      pickupArrivedAt: at(m['pickupArrivedAtMs']),
      returnArrivedAt: at(m['returnArrivedAtMs']),
      createdAt: at(m['createdAtMs']),
    );
  }

  Future<String> placeOrder({
    required int carpetCount,
    required String pickupAddress,
    double? pickupLat,
    double? pickupLng,
    String note = '',
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? _uuid.v4();
    final result = await _functions.httpsCallable('placeCarpetWashOrder').call({
      'carpetCount': carpetCount,
      'pickupAddress': pickupAddress.trim(),
      if (pickupLat != null) 'pickupLat': pickupLat,
      if (pickupLng != null) 'pickupLng': pickupLng,
      'note': note.trim(),
      'idempotencyKey': key,
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
    String? reason,
  }) async {
    await _functions.httpsCallable('adminSetCarpetWashStatus').call({
      'adminPhone': adminPhone,
      'orderId': orderId,
      'status': status,
      if (finalPrice != null) 'finalPrice': finalPrice,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
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
