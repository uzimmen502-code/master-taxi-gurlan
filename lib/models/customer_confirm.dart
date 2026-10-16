// Мижоз тасдиғи («Олдим» / «Бердим» / миқдорни тасдиқлаш) — модел ва соф
// мантиқ. Қарор D2/D7 (эга): ava-courier оқимида курьернинг «етиб келдим /
// олдим» тугмаси етарли эмас — мижоз ЎЗ қурилмасида тасдиқлайди; ёқилган
// мижоз учун МАЖБУРИЙ (авто-тасдиқ йўқ). Қоида ва ҳолатни СЕРВЕР назорат
// қилади (44-қоида): бу ерда фақат жавобни ўқиймиз ва матн калитини танлаймиз.
//
// Шартнома (сервер, us-central1):
//   • курьер callable'лари (courierCompleteRestaurantDelivery,
//     courierMarkCarpetPickedUp/Delivered, courierMarkAgroPickedUp,
//     courierFinalizeCollection) → `{ok, awaitingCustomer:true, step}` ёки эски жавоб;
//   • getCustomerPendingConfirmations({}) → `{ok, items:[…]}`;
//   • customerConfirmHandover({module,id,step}) → `{ok, status?, idempotent?}`;
//     хато `details.reason`: NOT_AWAITING · NOT_YOUR_ORDER · STATE_CHANGED.
// Эски сервер `awaitingCustomer`ни умуман қайтармайди → ҳамма нарса аввалгидек.

/// Курьер амали жавоби: якунланди ёки мижоз тасдиғи кутилмоқда.
class CourierActionResult {
  const CourierActionResult({this.awaitingCustomer = false, this.step = ''});

  /// `true` — мижоз тасдиқламагунча вазифа ўтмайди (муваффақият ҳам, хато ҳам эмас).
  final bool awaitingCustomer;

  /// Сервер қадами (`handover_pickup` …); бўш бўлиши мумкин.
  final String step;

  /// Эски сервер / оддий якун.
  static const completed = CourierActionResult();

  /// Қаттиқ `== true`: майдон йўқ, `null` ёки `"true"` (матн) бўлса — кутиш ЙЎҚ.
  factory CourierActionResult.fromResponse(Object? data) {
    if (data is! Map) return completed;
    if (data['awaitingCustomer'] != true) return completed;
    final step = data['step'];
    return CourierActionResult(
      awaitingCustomer: true,
      step: step is String ? step : '',
    );
  }
}

/// Мижоз тасдиғи модуллари (сервер `module`).
abstract final class CustomerConfirmModule {
  static const restaurant = 'restaurant';
  static const carpet = 'carpet';
  static const agro = 'agro';
  static const collection = 'collection';
}

/// Мижоз тасдиғи қадамлари (сервер `step`).
abstract final class CustomerConfirmStep {
  /// Мижоз буюмни курьерга топширди («Курьерга бердим»).
  static const handoverPickup = 'handover_pickup';

  /// Курьер буюмни мижозга қайтарди («Олдим»).
  static const handoverReturn = 'handover_return';

  /// Мижоз буюртмани олди («Олдим»).
  static const received = 'received';

  /// Йиғиш: курьер киритган миқдор/сумма («Тасдиқлайман»).
  static const finalize = 'finalize';
}

/// Тасдиқ тугмаси матни калити — қадамга қараб. Номаълум қадам (сервер
/// кейин қўшган) — умумий «Тасдиқлайман».
String customerConfirmButtonKey(String step) {
  switch (step) {
    case CustomerConfirmStep.handoverPickup:
      return 'customer_confirm_btn_handover';
    case CustomerConfirmStep.handoverReturn:
    case CustomerConfirmStep.received:
      return 'customer_confirm_btn_received';
    default:
      return 'customer_confirm_btn_confirm';
  }
}

/// Қадамга мос қисқа изоҳ калити (сервер `summary` бермаганда).
String customerConfirmHintKey(String step) {
  switch (step) {
    case CustomerConfirmStep.handoverPickup:
      return 'customer_confirm_hint_handover_pickup';
    case CustomerConfirmStep.handoverReturn:
      return 'customer_confirm_hint_handover_return';
    case CustomerConfirmStep.received:
      return 'customer_confirm_hint_received';
    case CustomerConfirmStep.finalize:
      return 'customer_confirm_hint_finalize';
    default:
      return 'customer_confirm_hint_generic';
  }
}

/// Сарлавҳа бўш келса — модул номи калити.
String customerConfirmModuleKey(String module) {
  switch (module) {
    case CustomerConfirmModule.restaurant:
      return 'customer_confirm_module_restaurant';
    case CustomerConfirmModule.carpet:
      return 'customer_confirm_module_carpet';
    case CustomerConfirmModule.agro:
      return 'customer_confirm_module_agro';
    case CustomerConfirmModule.collection:
      return 'customer_confirm_module_collection';
    default:
      return 'customer_confirm_module_generic';
  }
}

/// Сервер хато `details.reason` → мижозга кўринадиган матн калити.
/// Ички код мижозга кўрсатилмайди (25-қоида).
String customerConfirmErrorKey(String reason) {
  switch (reason) {
    case 'NOT_AWAITING':
      return 'customer_confirm_err_not_awaiting';
    case 'NOT_YOUR_ORDER':
      return 'customer_confirm_err_not_yours';
    case 'STATE_CHANGED':
      return 'customer_confirm_err_state_changed';
    default:
      return 'customer_confirm_err_generic';
  }
}

/// Хатодан кейин рўйхатни албатта янгилаш керакми (ҳолат сервер томонда
/// ўзгарган — эски карточка алдамасин).
bool customerConfirmErrorNeedsRefresh(String reason) =>
    reason == 'NOT_AWAITING' || reason == 'STATE_CHANGED' || reason == 'NOT_YOUR_ORDER';

/// Йиғиш (`finalize`) учун курьер киритган рақамлар.
class CustomerConfirmDetails {
  const CustomerConfirmDetails({
    this.qty,
    this.unit = '',
    this.amount,
    this.productLabel = '',
  });

  final num? qty;
  final String unit;

  /// Сўмда, бутун сон (8-қоида).
  final int? amount;
  final String productLabel;

  bool get isEmpty =>
      qty == null && amount == null && productLabel.isEmpty && unit.isEmpty;

  static CustomerConfirmDetails? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final q = raw['qty'];
    final a = raw['amount'];
    final d = CustomerConfirmDetails(
      qty: q is num ? q : null,
      unit: raw['unit'] is String ? raw['unit'] as String : '',
      amount: a is num ? a.toInt() : null,
      productLabel:
          raw['productLabel'] is String ? raw['productLabel'] as String : '',
    );
    return d.isEmpty ? null : d;
  }
}

/// Мижоз тасдиғини кутаётган битта элемент.
class CustomerConfirmation {
  const CustomerConfirmation({
    required this.module,
    required this.id,
    required this.step,
    this.title = '',
    this.summary = '',
    this.requestedAt,
    this.details,
  });

  final String module;
  final String id;
  final String step;
  final String title;
  final String summary;
  final DateTime? requestedAt;
  final CustomerConfirmDetails? details;

  /// Рўйхатда ва «банд» белгисида ягона калит (бир буюртмада икки қадам бўлиши мумкин).
  String get key => '$module/$id/$step';

  /// `module`/`id`/`step` бўш бўлса — тасдиқлаб бўлмайди → `null` (ўтказиб юборилади).
  static CustomerConfirmation? fromMap(Object? raw) {
    if (raw is! Map) return null;
    String s(String k) => raw[k] is String ? (raw[k] as String).trim() : '';
    final module = s('module');
    final id = s('id');
    final step = s('step');
    if (module.isEmpty || id.isEmpty || step.isEmpty) return null;
    final ms = raw['requestedAtMs'];
    return CustomerConfirmation(
      module: module,
      id: id,
      step: step,
      title: s('title'),
      summary: s('summary'),
      requestedAt:
          ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null,
      details: CustomerConfirmDetails.fromMap(raw['details']),
    );
  }

  /// `getCustomerPendingConfirmations` жавобидан рўйхат. Бузуқ элемент
  /// ташлаб юборилади; такрор калит битта бўлади; энг эскиси юқорида.
  static List<CustomerConfirmation> listFromResponse(Object? data) {
    if (data is! Map) return const [];
    final raw = data['items'];
    if (raw is! List) return const [];
    final seen = <String>{};
    final out = <CustomerConfirmation>[];
    for (final e in raw) {
      final c = CustomerConfirmation.fromMap(e);
      if (c != null && seen.add(c.key)) out.add(c);
    }
    out.sort((a, b) {
      final x = a.requestedAt;
      final y = b.requestedAt;
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      return x.compareTo(y);
    });
    return out;
  }
}

/// `customerConfirmHandover` натижаси.
class CustomerConfirmResult {
  const CustomerConfirmResult({this.status = '', this.idempotent = false});

  final String status;
  final bool idempotent;

  factory CustomerConfirmResult.fromResponse(Object? data) {
    if (data is! Map) return const CustomerConfirmResult();
    return CustomerConfirmResult(
      status: data['status'] is String ? data['status'] as String : '',
      idempotent: data['idempotent'] == true,
    );
  }
}

/// Мижоз тасдиғи хатоси: `reason` — сервер `details.reason`.
class CustomerConfirmException implements Exception {
  const CustomerConfirmException(this.code, this.reason, [this.message = '']);

  /// Firebase хато коди (`not-found`, `failed-precondition` …).
  final String code;

  /// `NOT_AWAITING` · `NOT_YOUR_ORDER` · `STATE_CHANGED` ёки бўш.
  final String reason;
  final String message;

  @override
  String toString() => 'CustomerConfirmException($code, $reason)';
}
