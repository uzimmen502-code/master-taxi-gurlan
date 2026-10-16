import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

import '../models/agro_pickup_order.dart';
import '../models/customer_confirm.dart';

/// Agro qabul (sut va h.k.) Cloud Functions wrapper.
class AgroPickupService {
  AgroPickupService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;
  static const _uuid = Uuid();

  /// `courierListAgroTasks` рўйхатлари: олиш учун (`accepted`) ва
  /// курьернинг ўзи олган `pickup_in_delivery` вазифалари.
  static const courierListPickup = 'pickup';
  static const courierListActive = 'active';

  /// Курьер вазифалари (`courierListAgroTasks`).
  ///
  /// `agro_pickup_orders` қоидаси курьерга рўйхат бермайди: қоида
  /// майдонларни кеса олмайди, сервер эса олишдан олдин
  /// ([courierListPickup]) ФАҚАТ id, маҳсулот, литр ва вақтни қайтаради —
  /// мижоз исми, телефони, манзили ва изоҳи вазифани олгандан кейин
  /// ([courierListActive], фақат шу курьерники) очилади (40-қоида).
  Future<List<AgroPickupOrder>> listCourierTasks(String list) async {
    final result = await _functions
        .httpsCallable('courierListAgroTasks')
        .call({'list': list});
    final data = Map<String, dynamic>.from(result.data as Map);
    final raw = (data['tasks'] as List?) ?? const [];
    final fallbackStatus =
        list == courierListPickup ? AgroPickupOrder.statusAccepted : '';
    return [
      for (final m in raw.whereType<Map>())
        courierTaskFromMap(
          Map<String, dynamic>.from(m),
          fallbackStatus: fallbackStatus,
        ),
    ];
  }

  /// `courierListAgroTasks` элементи → [AgroPickupOrder]. Олиш рўйхатида
  /// `status` ва мижоз майдонлари келмайди — улар бўш қолади.
  static AgroPickupOrder courierTaskFromMap(
    Map<String, dynamic> m, {
    String fallbackStatus = '',
  }) {
    DateTime? at(Object? ms) =>
        ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null;
    // Майдонсиз эски ҳужжат — `fromDoc` каби сут.
    final productType = (m['productType'] as String?) ?? '';
    return AgroPickupOrder(
      id: (m['id'] ?? '') as String,
      customerId: '',
      customerPhone: (m['customerPhone'] ?? '') as String,
      customerName: (m['customerName'] ?? '') as String,
      productType:
          productType.isEmpty ? AgroPickupOrder.productMilk : productType,
      pickupAddress: (m['pickupAddress'] ?? '') as String,
      literCount: (m['literCount'] as num?)?.toDouble() ?? 0,
      note: (m['note'] ?? '') as String,
      status: (m['status'] as String?) ?? fallbackStatus,
      arrivedAt: at(m['arrivedAtMs']),
      createdAt: at(m['createdAtMs']),
    );
  }

  Future<String> placeMilkOrder({
    required double literCount,
    required String pickupAddress,
    double? pickupLat,
    double? pickupLng,
    String note = '',
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? _uuid.v4();
    final result = await _functions.httpsCallable('placeAgroPickupOrder').call({
      'productType': 'milk',
      'literCount': literCount,
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
    await _functions.httpsCallable('adminSetAgroPickupStatus').call({
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

  /// «Олиб кетилди». Мижоз тасдиғи ёқилган бўлса сервер
  /// `awaitingCustomer: true` қайтаради — мижоз «Курьерга бердим»ни босмагунча
  /// вазифа ўтмайди (D2/D7). Эски сервер → [CourierActionResult.completed].
  Future<CourierActionResult> courierMarkPickedUp({
    required String courierPhone,
    required String orderId,
  }) async {
    final result = await _functions.httpsCallable('courierMarkAgroPickedUp').call({
      'courierPhone': courierPhone,
      'orderId': orderId,
    });
    return CourierActionResult.fromResponse(result.data);
  }
}
