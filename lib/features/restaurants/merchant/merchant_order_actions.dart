// Ресторан панели: буюртма ҳолати → мумкин бўлган ҳаракатлар (СОФ, тестланади).
// Сервердаги ўтиш жадвали билан бир хил (restaurant_orders.js):
//   placed   → accept | reject
//   accepted → ready  | reject
//   ready    → (o'z kuryeri / olib ketish) delivered | reject; AVA kuryeri — kutish
//   + prepay va to'lov kelmagan bo'lsa — confirmPayment (yakuniy bo'lmasa)

import '../../../models/order_model.dart';
import '../domain/restaurant_models.dart';

enum MerchantAction { accept, reject, ready, markDelivered, confirmPayment }

/// Ҳаракатлар — асосийси биринчи (UI катта тугма қилади).
List<MerchantAction> merchantActionsFor(OrderModel o) {
  final s = o.restaurantStatus;
  final out = <MerchantAction>[];
  switch (s) {
    case RestaurantOrderStatus.placed:
      out.addAll([MerchantAction.accept, MerchantAction.reject]);
      break;
    case RestaurantOrderStatus.accepted:
      out.addAll([MerchantAction.ready, MerchantAction.reject]);
      break;
    case RestaurantOrderStatus.ready:
      if (o.deliveryMode != 'ava_courier') out.add(MerchantAction.markDelivered);
      out.add(MerchantAction.reject);
      break;
    default:
      break;
  }
  if (!RestaurantOrderStatus.isTerminal(s) &&
      o.foodPaymentMethod == 'prepay' &&
      o.paymentStatus != 'paid') {
    out.add(MerchantAction.confirmPayment);
  }
  return out;
}

/// Inbox бўлимлари: янги · жараёнда · тарих.
enum MerchantOrderBucket { fresh, active, history }

MerchantOrderBucket merchantBucketFor(OrderModel o) {
  final s = o.restaurantStatus;
  if (s == RestaurantOrderStatus.placed) return MerchantOrderBucket.fresh;
  if (RestaurantOrderStatus.isTerminal(s)) return MerchantOrderBucket.history;
  return MerchantOrderBucket.active;
}

/// «Биринчи буюртма келди» табриги учун қоида (эга, 2026-10-31) — СОФ, тестланади.
///
/// Inbox оқимининг ҳар рўйхати [onList] га берилади. Табрик фақат шу ҳолатда:
/// 1) панел очилгандаги БИРИНЧИ рўйхат БЎШ эди (ресторанда умуман буюртма йўқ эди —
///    сўров фақат `restaurantId` бўйича, ҳолат/сана фильтрисиз);
/// 2) ундан кейинги БИРИНЧИ бўш бўлмаган рўйхат айнан БИТТА буюртма ва у янги (`placed`).
///
/// Эски буюртмалар (биринчи рўйхат бўш эмас) — ҳеч қачон. Биринчи бўш бўлмаган рўйхатда
/// бир нечта буюртма ёки янги бўлмагани бўлса — ҳам йўқ ва қоида шу панел учун ўчади:
/// масалан офлайн кешдан бўш рўйхат, кейин сервердан 30 та эски буюртма келса — «биринчи»
/// деб ёлғон табрик чиқмасин. «Панел очилгандан кейин яратилган» (`createdAt`) қоидаси
/// АТАЙИН ишлатилмайди: қурилма соати ва `serverTimestamp` фарқига боғлиқ, янги
/// қурилмада эса 50-буюртмани ҳам «биринчи» дерди.
class FirstOrderDetector {
  /// `null` — биринчи рўйхат ҳали келмаган; `true` — у бўш эди, кутиляпти; `false` — ўчиқ.
  bool? _armed;

  /// Табрик керак бўлса — ўша буюртма id'си (фақат БИР марта), акс ҳолда `null`.
  String? onList(List<OrderModel> list) {
    final armed = _armed;
    if (armed == null) {
      _armed = list.isEmpty;
      return null;
    }
    if (!armed || list.isEmpty) return null;
    _armed = false;
    final only = list.length == 1 ? list.single : null;
    return only != null && merchantBucketFor(only) == MerchantOrderBucket.fresh ? only.id : null;
  }
}

/// Қабул муддатигача қолган сониялар (манфий — ўтган; `null` — муддат йўқ).
int? secondsToDeadline(OrderModel o, DateTime now) {
  final d = o.acceptDeadlineAt;
  if (d == null) return null;
  return d.difference(now).inSeconds;
}
