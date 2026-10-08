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

/// Қабул муддатигача қолган сониялар (манфий — ўтган; `null` — муддат йўқ).
int? secondsToDeadline(OrderModel o, DateTime now) {
  final d = o.acceptDeadlineAt;
  if (d == null) return null;
  return d.difference(now).inSeconds;
}
