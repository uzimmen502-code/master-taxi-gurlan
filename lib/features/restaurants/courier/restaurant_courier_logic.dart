// AVA курьери томонидаги ресторан буюртмаси — СОФ мантиқ (тестланади).
// Сервер жадвали билан бир хил (restaurant_orders.js, TRANSITIONS):
//   accepted → ресторан тайёрлаяпти (курьер ресторанга боради, кутади)
//   ready    → courierPickupRestaurantOrder (ресторан коди) → picked
//   picked   → courierArriveRestaurantOrder → arrived   | delivery_failed
//   arrived  → courierCompleteRestaurantDelivery → delivered | delivery_failed
// Пул: таом пули AVA'ники ЭМАС (D-REST-1) — курьер фақат нақд выкуп ва
// нақд етказиш ҳақини мижоздан олади; ҳамён ечими серверда.

import '../../../models/customer_confirm.dart';
import '../../../models/order_model.dart';
import '../domain/restaurant_models.dart';

enum CourierRestaurantStage {
  /// `placed`/`accepted` — ресторан тайёрлаяпти; курьер ресторанга боради.
  preparing,

  /// `ready` — ресторан кодини киритиб олиб кетади.
  pickup,

  /// `picked` — мижозга кетмоқда.
  toCustomer,

  /// `arrived` — топшириш ва нақд (бўлса) олиш.
  handover,

  /// `delivered`.
  done,

  /// `rejected` · `cancelled` · `delivery_failed`.
  cancelled,
}

CourierRestaurantStage courierStageFor(OrderModel o) {
  switch (o.restaurantStatus) {
    case RestaurantOrderStatus.ready:
      return CourierRestaurantStage.pickup;
    case RestaurantOrderStatus.picked:
      return CourierRestaurantStage.toCustomer;
    case RestaurantOrderStatus.arrived:
      return CourierRestaurantStage.handover;
    case RestaurantOrderStatus.delivered:
      return CourierRestaurantStage.done;
    case RestaurantOrderStatus.rejected:
    case RestaurantOrderStatus.cancelled:
    case RestaurantOrderStatus.deliveryFailed:
      return CourierRestaurantStage.cancelled;
    default:
      return CourierRestaurantStage.preparing;
  }
}

/// Курьер учун буюртма тугаган (маршрут индекси олдинга сурилади).
/// Эски `effectivePayment == 'paid'` белгиси ЯРАМАЙДИ: олдиндан тўланган
/// ресторан буюртмаси етказилгунча «paid» бўлади.
bool isRestaurantOrderFinalized(OrderModel o) =>
    RestaurantOrderStatus.isTerminal(o.restaurantStatus);

/// Нақд буюртмада курьер ресторанга тўлайдиган сумма (выкуп); акс ҳолда 0.
int courierBuyoutAmount(OrderModel o) =>
    o.foodPaymentMethod == 'cash_buyout' ? o.foodAmount : 0;

/// Топширишда мижоздан олинадиган НАҚД: выкуп + (етказиш нақд бўлса) ҳақи.
/// Етказиш «ҳамён» бўлса сервер мижоз ҳамёнидан ечади; етмаса нақдга
/// тушади — буни сервер натижаси айтади ([CourierCompletionSummary]).
int courierCashToCollect(OrderModel o) =>
    courierBuyoutAmount(o) + (o.deliveryPaymentMethod == 'cash' ? o.deliveryFee : 0);

/// Мижоз тасдиғи кутилаётган буюртма: курьер амали `awaitingCustomer`
/// қайтарган пайтдаги ҳолат ([awaitingStatus]) ҳалигача ўша бўлса — кутиш
/// давом этмоқда. Ҳолат ўзгарса (мижоз тасдиқлади ёки бекор бўлди) — йўқолади.
bool courierIsAwaitingCustomer(OrderModel o, String? awaitingStatus) =>
    awaitingStatus != null && awaitingStatus == o.restaurantStatus;

/// Кутиш бошланган, кейин буюртма якунланди (мижоз «Олдим» босди) →
/// курьерга «Кейинги буюртма» тугмаси чиқади: етказиш натижаси диалоги
/// кутиш пайтида кўрсатилмаганди.
bool courierAwaitingFinished(OrderModel o, String? awaitingStatus) =>
    awaitingStatus != null && isRestaurantOrderFinalized(o);

/// «Етказиб бўлмади» фақат қўлдаги буюртмада (`picked`/`arrived`).
bool courierCanFail(OrderModel o) =>
    o.restaurantStatus == RestaurantOrderStatus.picked ||
    o.restaurantStatus == RestaurantOrderStatus.arrived;

/// Навигация нишони: олгунча — ресторан, кейин — мижоз. Координата
/// бўлмаса `null`.
({double lat, double lng})? courierNavTarget(OrderModel o) {
  final stage = courierStageFor(o);
  final toRestaurant = stage == CourierRestaurantStage.preparing ||
      stage == CourierRestaurantStage.pickup;
  if (toRestaurant) {
    if (!o.hasRestaurantCoordinates) return null;
    return (lat: o.restaurantLat!, lng: o.restaurantLng!);
  }
  if (!o.hasCoordinates) return null;
  return (lat: o.lat!, lng: o.lng!);
}

/// Сервер `FAIL_REASONS` билан бир хил; матн — `restaurants_courier_fail_*`.
const courierFailReasons = [
  'customer_absent',
  'customer_refused',
  'courier_problem',
  'other',
];

/// `courierCompleteRestaurantDelivery` натижаси — курьерга кўрсатиш учун.
class CourierCompletionSummary {
  const CourierCompletionSummary({
    required this.delivered,
    required this.cashCollected,
    required this.walletPaid,
    required this.deliveryFee,
    required this.walletFallback,
    this.awaitingCustomer = false,
    this.awaitingStep = '',
  });

  /// Мижоз тасдиғи (D2/D7): сервер `awaitingCustomer: true` қайтарса, буюртма
  /// ҳали ЕТКАЗИЛМАГАН — мижоз «Олдим»ни босмагунча ўтмайди. Бу ҳолда
  /// [delivered] ва пул майдонлари маъносиз (муваффақият ҳам, хато ҳам эмас).
  final bool awaitingCustomer;
  final String awaitingStep;

  final bool delivered;

  /// Мижоздан нақд олинган жами (выкуп + нақд етказиш).
  final int cashCollected;

  /// Мижоз ҳамёнидан курьерга ўтган етказиш ҳақи.
  final int walletPaid;
  final int deliveryFee;

  /// Ҳамён етмади — етказиш ҳақи нақдга тушди (`deliveryFeeFallback`).
  final bool walletFallback;

  factory CourierCompletionSummary.fromMap(Map<String, dynamic> m, {required OrderModel order}) {
    final outcome = (m['outcome'] ?? '') as String;
    final delivered = outcome == 'delivered';
    final method = (m['deliveryPaymentMethod'] ?? '') as String;
    final walletPaid = (m['walletPaid'] as num?)?.toInt() ?? 0;
    final wait = CourierActionResult.fromResponse(m);
    return CourierCompletionSummary(
      awaitingCustomer: wait.awaitingCustomer,
      awaitingStep: wait.step,
      delivered: delivered,
      cashCollected: (m['cashCollected'] as num?)?.toInt() ?? 0,
      walletPaid: walletPaid,
      deliveryFee: (m['deliveryFee'] as num?)?.toInt() ?? order.deliveryFee,
      walletFallback: delivered &&
          order.deliveryPaymentMethod == 'wallet' &&
          method == 'cash' &&
          walletPaid == 0,
    );
  }
}
