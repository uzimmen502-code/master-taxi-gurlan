import 'package:cloud_functions/cloud_functions.dart';

import '../models/order_model.dart';

/// Kuryer o'zi MFY tanlab `delivery_routes` yaratadi (Cloud Function).
class CourierRouteService {
  CourierRouteService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// Маршрут қуриш экрани учун `ready` буюртмалар (`courierListReadyOrders`).
  ///
  /// `orders` қоидаси курьерга рўйхат бермайди: қоида майдонларни кеса
  /// олмайди, сервер эса олишдан олдин ФАҚАТ `id`, МФЙ ва координатани
  /// қайтаради — мижоз телефони, исми, манзили ва савати курьерга буюртма
  /// маршрутига тушгандан кейин очилади (40-қоида). Шунинг учун қайтган
  /// [OrderModel]ларнинг бошқа майдонлари бўш.
  Future<List<OrderModel>> listReadyOrders() async {
    final result =
        await _functions.httpsCallable('courierListReadyOrders').call();
    final data = Map<String, dynamic>.from(result.data as Map);
    final raw = (data['orders'] as List?) ?? const [];
    return [
      for (final m in raw.whereType<Map>())
        readyStopFromMap(Map<String, dynamic>.from(m)),
    ];
  }

  /// `courierListReadyOrders` элементи → [OrderModel] (фақат маршрут майдонлари).
  static OrderModel readyStopFromMap(Map<String, dynamic> m) {
    final createdMs = (m['createdAtMs'] as num?)?.toInt();
    return OrderModel(
      id: (m['id'] ?? '') as String,
      type: '',
      total: 0,
      status: 'ready',
      items: const [],
      mfy: m['mfy'] as String?,
      lat: (m['lat'] as num?)?.toDouble(),
      lng: (m['lng'] as num?)?.toDouble(),
      createdAt: createdMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(createdMs),
    );
  }

  Future<({String? routeId, int count, String? error})> createRoute({
    required String courierPhone,
    required List<String> orderedOrderIds,
  }) async {
    if (courierPhone.trim().isEmpty) {
      return (routeId: null, count: 0, error: 'Курьер телефони аниқланмади');
    }
    if (orderedOrderIds.isEmpty) {
      return (routeId: null, count: 0, error: 'Буюртмалар танланмади');
    }

    try {
      final result = await _functions.httpsCallable('courierCreateRoute').call({
        'courierPhone': courierPhone,
        'orderedOrderIds': orderedOrderIds,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final routeId = data['routeId'] as String?;
      final count = (data['count'] as num?)?.toInt() ?? orderedOrderIds.length;
      if (routeId == null || routeId.isEmpty) {
        return (routeId: null, count: 0, error: 'routeId йўқ');
      }
      return (routeId: routeId, count: count, error: null);
    } on FirebaseFunctionsException catch (e) {
      return (routeId: null, count: 0, error: e.message ?? e.code);
    } catch (e) {
      return (routeId: null, count: 0, error: e.toString());
    }
  }

  /// Хавфсизлик тўри: фаол маршрут йўқ бўлса, курьернинг `in_delivery` +
  /// тўланмаган буюртмаларидан автоматик маршрут тиклашга уринади.
  Future<({String? routeId, int count, bool revived})> recoverOrphanRoute({
    required String courierPhone,
  }) async {
    if (courierPhone.trim().isEmpty) {
      return (routeId: null, count: 0, revived: false);
    }
    try {
      final result =
          await _functions.httpsCallable('courierRecoverOrphanRoute').call({
        'courierPhone': courierPhone,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return (
        routeId: data['routeId'] as String?,
        count: (data['count'] as num?)?.toInt() ?? 0,
        revived: data['revived'] == true,
      );
    } catch (_) {
      return (routeId: null, count: 0, revived: false);
    }
  }
}
