// Буюртмани топшириш (эга, 2026-10-31): бошқа курьерга ёки ресторанга.
// Қоида ва ҳолат — серверда (`courierStartRestaurantHandover`,
// `courierAcceptRestaurantHandover`, `restaurantAcceptReturn`); бу ерда фақат
// жавобни ўқиш ва кўрсатиш учун соф мантиқ (тестланади).

import '../../../models/order_model.dart';
import 'restaurant_models.dart';

/// Топширишни бошлаш жавоби.
class HandoverStart {
  const HandoverStart({this.released = false, this.code = '', this.expiresAt, this.searchUntil});

  /// Олишдан олдин: буюртма дарҳол қўйиб юборилди (код йўқ).
  final bool released;

  /// 6 хонали код (олгандан кейин) — бошқа курьерга ёки ресторанга айтилади.
  final String code;
  final DateTime? expiresAt;
  final DateTime? searchUntil;

  static DateTime? _ms(Object? v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

  factory HandoverStart.fromMap(Map<String, dynamic> m) => HandoverStart(
        released: m['released'] == true,
        code: m['code'] is String ? m['code'] as String : '',
        expiresAt: _ms(m['expiresAtMs']),
        searchUntil: _ms(m['searchUntilMs']),
      );
}

/// Курьер «Топшириш» тугмасини кўрадими: ўз қўлидаги ёки олиш учун бораётган
/// буюртма, «етказилмади» кутилмаётган бўлса.
bool courierCanHandover(OrderModel o) {
  final s = o.restaurantStatus;
  final active = s == RestaurantOrderStatus.accepted ||
      s == RestaurantOrderStatus.ready ||
      s == RestaurantOrderStatus.picked ||
      s == RestaurantOrderStatus.arrived;
  return o.isRestaurant && active && !o.isDeliveryFailedPending;
}

/// Олишдан олдинми (жисмоний топшириш йўқ — фақат қўйиб юбориш).
bool handoverIsRelease(OrderModel o) =>
    o.restaurantStatus == RestaurantOrderStatus.accepted || o.restaurantStatus == RestaurantOrderStatus.ready;

/// Нақд выкуп буюртмасини бошқа курьерга бериш ҳозирча йўқ (сервер ҳам рад этади).
bool handoverToCourierAllowed(OrderModel o) =>
    handoverIsRelease(o) || o.foodPaymentMethod != 'cash_buyout';

/// Код: аниқ 6 рақам.
bool isHandoverCode(String s) => RegExp(r'^\d{6}$').hasMatch(s.trim());
