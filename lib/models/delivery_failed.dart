// «Етказилмади» — нон/бозор, гилам, сут, йиғиш (эга қарорлари 2026-10-31).
// Сервер: `functions/delivery_failed.js` (default codebase, us-central1):
//   • courierReportDeliveryFailed({module, id, reason}) → {ok, awaitingCustomer:true, step, escalateAtMs}
//   • resolveDeliveryFailed({module, id, decision:'failed'|'continue'}) → {ok, status, decision, idempotent?}
//   • listDeliveryFailedPending({}) → {ok, items:[…]} (сотувчи — нон/бозор; админ — ҳаммаси)
// Ҳолат ва рухсат СЕРВЕРДА (44-қоида): бу ерда фақат жавобни ўқиймиз ва матн калитини танлаймиз.

import 'package:cloud_firestore/cloud_firestore.dart';

/// Сервер модул калитлари (customer_confirm билан бир хил).
abstract final class DeliveryFailedModule {
  static const order = 'order';
  static const carpet = 'carpet';
  static const agro = 'agro';
  static const collection = 'collection';

  /// «Менинг бизнесим» маҳсулот буюртмаси (`orders`, type business); қарор — шу буюртма сотувчиси ёки админ.
  static const business = 'business';
}

/// Курьер сабаблари — сервер `FAIL_REASONS` (restaurant_orders.js) билан бир хил.
const deliveryFailedReasons = [
  'customer_absent',
  'customer_refused',
  'courier_problem',
  'other',
];

/// Сабаб → матн калити (курьер панелидаги мавжуд калитлар; номаълум — «бошқа»).
String deliveryFailedReasonKey(String reason) =>
    deliveryFailedReasons.contains(reason) && reason != 'other'
        ? 'restaurants_courier_fail_$reason'
        : 'restaurants_courier_fail_other';

/// Ҳужжатдаги «етказилмади» кутиш ҳолати (курьер ва мижоз экранлари учун).
class DeliveryFailedState {
  const DeliveryFailedState({
    this.pending = false,
    this.reason = '',
    this.deadline,
    this.escalated = false,
    this.leg = '',
  });

  /// Курьер «етказилмади» деди — мижоз ёки сотувчи/админ қарори кутилмоқда.
  final bool pending;
  final String reason;

  /// Шу вақтгача мижоз жавоб беради, кейин қарор сотувчи/админга ўтади.
  final DateTime? deadline;

  /// Мижоз жавоб бермади — қарор сотувчи/админда.
  final bool escalated;

  /// `delivery` (нон), `pickup` (олиб кетиш), `return` (гилам қайтариш).
  final String leg;

  static const none = DeliveryFailedState();

  /// Олиб кетиш (мижоз беради) — тугма ва матнлар «олиб бўлмади» шаклида.
  bool get isPickup => leg == 'pickup';

  /// Курьер рўйхати callable проекцияси (`courierListCarpetTasks` / `courierListAgroTasks`).
  /// Майдон йўқ (эски сервер) — кутиш йўқ.
  factory DeliveryFailedState.fromCallable(Map<dynamic, dynamic> m, {String leg = ''}) {
    if (m['deliveryFailedPending'] != true) return none;
    final ms = m['deliveryFailedEscalateAtMs'];
    return DeliveryFailedState(
      pending: true,
      reason: m['deliveryFailedReason'] is String ? m['deliveryFailedReason'] as String : '',
      deadline: ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null,
      escalated: m['deliveryFailedEscalated'] == true,
      leg: leg,
    );
  }

  /// Firestore ҳужжатидан (мижоз ўз ҳужжатини ўқийди; курьер — йиғиш вазифаси, нон буюртмаси).
  /// Фақат шу модулнинг белгиси ҳисобга олинади (`awaitingCustomerConfirm.module`).
  factory DeliveryFailedState.fromDoc(Map<String, dynamic> d, String module) {
    final m = d['awaitingCustomerConfirm'];
    if (m is! Map || m['step'] != 'delivery_failed' || m['module'] != module) return none;
    final esc = m['escalateAt'];
    return DeliveryFailedState(
      pending: true,
      reason: m['failReason'] is String ? m['failReason'] as String : '',
      deadline: esc is Timestamp ? esc.toDate() : null,
      escalated: d['deliveryFailedEscalatedAt'] != null,
      leg: m['leg'] is String ? m['leg'] as String : '',
    );
  }
}

/// Сотувчи/админ рўйхатидаги битта элемент (`listDeliveryFailedPending`).
class DeliveryFailedPendingItem {
  const DeliveryFailedPendingItem({
    required this.module,
    required this.id,
    this.leg = '',
    this.status = '',
    this.failReason = 'other',
    this.requestedAt,
    this.escalateAt,
    this.escalated = false,
    this.canDecide = false,
    this.customerName = '',
    this.customerPhoneTail = '',
    this.address = '',
    this.total,
    this.courierTail = '',
  });

  final String module;
  final String id;
  final String leg;
  final String status;
  final String failReason;
  final DateTime? requestedAt;
  final DateTime? escalateAt;
  final bool escalated;

  /// Сервер: муддат ўтган ёки эскалация бўлган — қарор тугмалари ёқилади.
  final bool canDecide;
  final String customerName;
  final String customerPhoneTail;
  final String address;

  /// Фақат нон/бозор: буюртма жами (сўм, бутун сон).
  final int? total;
  final String courierTail;

  String get key => '$module/$id';

  static DeliveryFailedPendingItem? fromMap(Object? raw) {
    if (raw is! Map) return null;
    String s(String k) => raw[k] is String ? (raw[k] as String).trim() : '';
    DateTime? t(String k) => raw[k] is num ? DateTime.fromMillisecondsSinceEpoch((raw[k] as num).toInt()) : null;
    final module = s('module');
    final id = s('id');
    if (module.isEmpty || id.isEmpty) return null;
    return DeliveryFailedPendingItem(
      module: module,
      id: id,
      leg: s('leg'),
      status: s('status'),
      failReason: s('failReason').isEmpty ? 'other' : s('failReason'),
      requestedAt: t('requestedAtMs'),
      escalateAt: t('escalateAtMs'),
      escalated: raw['escalated'] == true,
      canDecide: raw['canDecide'] == true,
      customerName: s('customerName'),
      customerPhoneTail: s('customerPhoneTail'),
      address: s('address'),
      total: raw['total'] is num ? (raw['total'] as num).toInt() : null,
      courierTail: s('courierTail'),
    );
  }

  static List<DeliveryFailedPendingItem> listFromResponse(Object? data) {
    if (data is! Map || data['items'] is! List) return const [];
    final seen = <String>{};
    final out = <DeliveryFailedPendingItem>[];
    for (final e in data['items'] as List) {
      final it = fromMap(e);
      if (it != null && seen.add(it.key)) out.add(it);
    }
    return out;
  }
}

/// Модул номи калити (сотувчи/админ рўйхати).
String deliveryFailedModuleKey(String module, String leg) => switch (module) {
      DeliveryFailedModule.order => 'delivery_failed_module_order',
      DeliveryFailedModule.carpet =>
        leg == 'return' ? 'delivery_failed_module_carpet_return' : 'delivery_failed_module_carpet_pickup',
      DeliveryFailedModule.agro => 'delivery_failed_module_agro',
      DeliveryFailedModule.collection => 'delivery_failed_module_collection',
      DeliveryFailedModule.business => 'biz_order_module',
      _ => 'customer_confirm_module_generic',
    };

/// Сервер `details.reason` → фойдаланувчига матн калити (ички код кўрсатилмайди, 25-қоида).
String deliveryFailedErrorKey(String reason) => switch (reason) {
      'DF_ARRIVE_FIRST' => 'delivery_failed_err_arrive_first',
      'DF_PAYMENT_SUBMITTED' => 'delivery_failed_err_paid',
      'DECISION_NOT_YET' => 'delivery_failed_err_not_yet',
      'DF_NOT_ACTIVE' || 'DF_NOT_AWAITING_DECISION' || 'STATE_CHANGED' => 'delivery_failed_err_state',
      'DF_NOT_ALLOWED' || 'DF_NOT_YOUR_TASK' => 'delivery_failed_err_not_allowed',
      _ => 'delivery_failed_err_generic',
    };

/// «Етказилмади» хатоси: `reason` — сервер `details.reason`.
class DeliveryFailedException implements Exception {
  const DeliveryFailedException(this.code, this.reason);

  final String code;
  final String reason;

  @override
  String toString() => 'DeliveryFailedException($code, $reason)';
}
