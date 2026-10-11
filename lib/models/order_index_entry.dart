import 'package:cloud_firestore/cloud_firestore.dart';

/// «Барча буюртмалар» — `order_index/{id}` (сервер ёзади, фақат ҳозирги
/// ҳолат; functions/order_index.js). «Тиқилиб қолган» вақти (`stuckAt`)
/// серверда ҳисобланади — бу ерда фақат солиштирилади (44-банд).
class OrderIndexEntry {
  const OrderIndexEntry({
    required this.id,
    required this.module,
    required this.sourceCollection,
    required this.sourceId,
    required this.normStatus,
    required this.stage,
    required this.rawStatus,
    this.final_ = false,
    this.courierId,
    this.hasCourier = false,
    this.amount,
    this.regionId,
    this.districtId,
    this.customerTail = '',
    this.title = '',
    this.createdAt,
    this.stageSince,
    this.cycleSince,
    this.stuckAt,
    this.stuckRule,
    this.sinceApprox = false,
  });

  final String id;
  final String module;
  final String sourceCollection;
  final String sourceId;
  final String normStatus;
  final String stage;
  final String rawStatus;
  final bool final_;
  final String? courierId;
  final bool hasCourier;
  final int? amount;
  final String? regionId;
  final String? districtId;

  /// Мижоз телефонининг охирги 4 рақами (тўлиқ PII индексда йўқ).
  final String customerTail;
  final String title;
  final DateTime? createdAt;
  final DateTime? stageSince;
  final DateTime? cycleSince;
  final DateTime? stuckAt;
  final String? stuckRule;

  /// Эски буюртма: «ҳолатга ўтган вақт» тахминий (backfill).
  final bool sinceApprox;

  static DateTime? _dt(Object? v) => v is Timestamp ? v.toDate() : null;

  factory OrderIndexEntry.fromMap(String id, Map<String, dynamic> d) {
    return OrderIndexEntry(
      id: id,
      module: (d['module'] ?? '') as String,
      sourceCollection: (d['sourceCollection'] ?? '') as String,
      sourceId: (d['sourceId'] ?? '') as String,
      normStatus: (d['normStatus'] ?? 'UNKNOWN') as String,
      stage: (d['stage'] ?? '') as String,
      rawStatus: (d['rawStatus'] ?? '') as String,
      final_: d['final'] == true,
      courierId: d['courierId'] as String?,
      hasCourier: d['hasCourier'] == true,
      amount: (d['amount'] as num?)?.toInt(),
      regionId: d['regionId'] as String?,
      districtId: d['districtId'] as String?,
      customerTail: (d['customerTail'] ?? '') as String,
      title: (d['title'] ?? '') as String,
      createdAt: _dt(d['createdAt']),
      stageSince: _dt(d['stageSince']),
      cycleSince: _dt(d['cycleSince']),
      stuckAt: _dt(d['stuckAt']),
      stuckRule: d['stuckRule'] as String?,
      sinceApprox: d['sinceApprox'] == true,
    );
  }

  factory OrderIndexEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      OrderIndexEntry.fromMap(doc.id, doc.data() ?? const {});

  bool isStuck(DateTime now) =>
      !final_ && stuckAt != null && !now.isBefore(stuckAt!);

  /// Шу ҳолатда қанча вақт турибди.
  Duration? inStageFor(DateTime now) =>
      stageSince == null ? null : now.difference(stageSince!);

  /// Чегарадан қанча ўтди (тиқилиб қолмаган бўлса — null).
  Duration? overdueBy(DateTime now) =>
      isStuck(now) ? now.difference(stuckAt!) : null;

  String get moduleLabel => moduleLabels[module] ?? module;
  String get statusLabel => statusLabels[normStatus] ?? normStatus;
  String get stageLabel => stageLabels[stage] ?? stage;

  /// Модул номлари (админ матнлари кирилл — бошқа админ экранлари каби).
  static const moduleLabels = <String, String>{
    'bread': 'Нон',
    'wholesale': 'Улгуржи',
    'restaurant': 'Кафе-ресторан',
    'carpet': 'Гилам ювиш',
    'milk': 'Сут қабул',
    'logistics': 'AVA Logistics',
    'courier': 'Курьер',
  };

  /// Ягона ҳолатлар — экран тартиби.
  static const statusOrder = <String>[
    'NEW',
    'ACCEPTED',
    'WAITING_COURIER',
    'WITH_COURIER',
    'DELIVERED',
    'CANCELLED',
  ];

  static const statusLabels = <String, String>{
    'NEW': 'Янги',
    'ACCEPTED': 'Қабул қилинди',
    'WAITING_COURIER': 'Курьер кутмоқда',
    'WITH_COURIER': 'Курьерда',
    'DELIVERED': 'Етказилди',
    'CANCELLED': 'Бекор',
    'UNKNOWN': 'Номаълум',
  };

  /// Босқич — тафсилотда (модулга хос аниқ ҳолат).
  static const stageLabels = <String, String>{
    'new': 'Янги',
    'accepted': 'Қабул қилинган',
    'preparing': 'Тайёрланмоқда',
    'waiting_courier': 'Курьер кутмоқда',
    'with_courier': 'Курьерда',
    'waiting_pickup': 'Мижоз олиб кетишини кутмоқда',
    'pickup_wait': 'Олиб кетишни кутмоқда',
    'pickup_transit': 'Курьер олиб кетмоқда',
    'processing': 'Ювилмоқда / қуримоқда',
    'ready_return': 'Тайёр, қайтарилмаган',
    'return_transit': 'Қайтарилмоқда',
    'collected': 'Олинди, якунланмаган',
    'awaiting_payment': 'Тўлов кутилмоқда',
    'unassigned': 'Ташувчи топилмаган',
    'leg_accepted': 'Ташувчи олди, юк олинмаган',
    'leg_local_transit': 'Маҳаллий бўлакда йўлда',
    'leg_linehaul_transit': 'Вилоятлараро йўлда',
    'leg_expired': 'Бўлак муддати ўтди',
    'no_courier': 'Курьер қидирилмоқда',
    'in_progress': 'Бажарилмоқда',
    'draft': 'Қоралама',
    'done': 'Якунланди',
    'cancelled': 'Бекор қилинди',
    'unknown': 'Номаълум',
  };

  /// Буюртма қайси админ бўлимида бошқарилади (фақат кўриш экрани —
  /// ҳаракатлар ўша бўлимда, D-ALL-3).
  String get managedInSection => switch (module) {
        'bread' || 'wholesale' => 'Буюртмалар → Доска',
        'restaurant' => 'Кафе-ресторанлар',
        'carpet' => 'Gilam yuvish',
        'milk' => 'Sut qabul',
        'logistics' => 'AVA Logistics',
        'courier' => 'Курьер',
        _ => '—',
      };
}

/// Қисқа «42 дақ» / «3 соат 5 дақ» / «2 кун 4 соат».
String formatAge(Duration d) {
  if (d.isNegative) return '0 дақ';
  final days = d.inDays;
  final hours = d.inHours % 24;
  final mins = d.inMinutes % 60;
  if (days > 0) return hours > 0 ? '$days кун $hours соат' : '$days кун';
  if (d.inHours > 0) return mins > 0 ? '${d.inHours} соат $mins дақ' : '${d.inHours} соат';
  return '${d.inMinutes} дақ';
}
