// «AVA Супермаркет» 3-босқич — ҲИСОБОТЛАР (эга 2026-11-21). Тизим ҳеч нарса сотиб олмайди, фақат ҳисоблайди.
//
// Сервер (functions/supermarket_reports.js, feat/supermarket-srv 6480789b):
//   • `adminSupermarketProcurementReport({date})` — admin/superadmin/dispatcher → `{date, orderCount, truncated,
//     stockIsNetOfReservations, offers[{productId, name, packLabel, groupId, groupNames, categoryId, categoryNames,
//     varietyId, varietyNames, unit, weighed, demandQty, stock|null, shortfall, orderCount, productMissing}], groups, categories}`;
//   • `adminSupermarketStats({from, to, backfill?})` — фақат admin/superadmin, ≤92 кун → `{days[], missing[], backfilled[],
//     partial[], summary, listsWithReminders}`. Курьер тўлови UNKNOWN → `courierPayout`/`netLogistics` null.
// Бу ердаги ҳисоб (захира %, CSV) — фақат кўрсатиш: серверга ҳеч нарса ёзилмайди.

import 'dart:math' as math;

int _i(Object? v) => v is num ? v.toInt() : 0;
int? _iN(Object? v) => v is num ? v.toInt() : null;
Map<String, String> _names(Object? v) =>
    v is Map ? {for (final e in v.entries) '${e.key}': '${e.value}'} : const {};
Map<String, num> _qtyMap(Object? v) =>
    v is Map ? {for (final e in v.entries) if (e.value is num) '${e.key}': e.value as num} : const {};

/// Сонни милли-бирликка (бутун) — каср хатосиз ҳисоб учун (сервер toMilli билан бир хил).
int smReportMilli(num v) => (v * 1000).round();

/// Тавсия этилган харид = ceil(shortfall + demand × захира% / 100), бутун бирликда (кг/л/дона).
/// Бутун арифметика: (shortMilli×100 + demandMilli×pct) / 100000, юқорига.
int smSuggestedPurchase({required num shortfall, required num demand, required int reservePercent}) {
  final pct = reservePercent.clamp(0, 500);
  final s = math.max(0, smReportMilli(shortfall));
  final d = math.max(0, smReportMilli(demand));
  final total = s * 100 + d * pct;
  if (total <= 0) return 0;
  return (total + 100000 - 1) ~/ 100000;
}

class SmProcurementOffer {
  const SmProcurementOffer({
    required this.productId,
    required this.name,
    this.packLabel,
    required this.groupId,
    this.groupNames = const {},
    required this.categoryId,
    this.categoryNames = const {},
    this.varietyId,
    this.varietyNames = const {},
    required this.unit,
    this.weighed = false,
    required this.demandQty,
    this.stock,
    this.reserved = 0,
    this.onHand,
    required this.shortfall,
    required this.orderCount,
    this.productMissing = false,
  });

  final String productId;
  final String name;
  final String? packLabel;
  final String groupId;
  final Map<String, String> groupNames;
  final String categoryId;
  final Map<String, String> categoryNames;
  final String? varietyId;
  final Map<String, String> varietyNames;
  final String unit;
  final bool weighed;
  final num demandQty;
  /// «Бўш қолдиқ» — сотилмаган (буюртмада камаяди).
  final num? stock;

  /// Очиқ (new/accepted/ready) буюртмаларда банд.
  final num reserved;

  /// «Жисмоний қолдиқ» = stock + reserved (сервер ҳисоблайди, эга 2026-11-26).
  final num? onHand;
  final num shortfall;
  final int orderCount;
  final bool productMissing;

  String get groupName => groupNames['uz_Cyrl'] ?? groupId;
  String get categoryName => categoryNames['uz_Cyrl'] ?? (categoryId == 'unknown' ? 'Бўлимсиз' : categoryId);
  String get varietyName => varietyNames['uz_Cyrl'] ?? (varietyId ?? '');

  factory SmProcurementOffer.fromMap(Map m) => SmProcurementOffer(
        productId: '${m['productId'] ?? ''}',
        name: '${m['name'] ?? m['productId'] ?? ''}',
        packLabel: m['packLabel'] is String ? m['packLabel'] as String : null,
        groupId: '${m['groupId'] ?? 'unknown'}',
        groupNames: _names(m['groupNames']),
        categoryId: '${m['categoryId'] ?? 'unknown'}',
        categoryNames: _names(m['categoryNames']),
        varietyId: m['varietyId'] is String ? m['varietyId'] as String : null,
        varietyNames: _names(m['varietyNames']),
        unit: '${m['unit'] ?? 'piece'}',
        weighed: m['weighed'] == true,
        demandQty: m['demandQty'] is num ? m['demandQty'] as num : 0,
        stock: m['stock'] is num ? m['stock'] as num : null,
        reserved: m['reserved'] is num ? m['reserved'] as num : 0,
        onHand: m['onHand'] is num ? m['onHand'] as num : null,
        shortfall: m['shortfall'] is num ? m['shortfall'] as num : 0,
        orderCount: _i(m['orderCount']),
        productMissing: m['productMissing'] == true,
      );
}

class SmProcurementReport {
  const SmProcurementReport({
    required this.date,
    required this.orderCount,
    required this.offers,
    this.truncated = false,
    this.stockIsNetOfReservations = false,
  });

  final String date;
  final int orderCount;
  final List<SmProcurementOffer> offers;
  final bool truncated;
  final bool stockIsNetOfReservations;

  factory SmProcurementReport.fromMap(Map<String, dynamic> m) => SmProcurementReport(
        date: '${m['date'] ?? ''}',
        orderCount: _i(m['orderCount']),
        truncated: m['truncated'] == true,
        stockIsNetOfReservations: m['stockIsNetOfReservations'] == true,
        offers: [
          if (m['offers'] is List)
            for (final o in m['offers'] as List)
              if (o is Map) SmProcurementOffer.fromMap(o),
        ],
      );

  /// Бўлим бўйича гуруҳлаш (сервер тартиби сақланади).
  Map<String, List<SmProcurementOffer>> byCategory() {
    final out = <String, List<SmProcurementOffer>>{};
    for (final o in offers) {
      (out[o.categoryName] ??= []).add(o);
    }
    return out;
  }
}

const smUnitTextRu = <String, String>{'kg': 'кг', 'l': 'л', 'piece': 'дона', 'pack': 'қадоқ', 'bunch': 'боғ'};

String _num(num v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  var s = v.toStringAsFixed(3);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

String smCsvCell(String v) {
  final needs = v.contains(',') || v.contains('"') || v.contains('\n') || v.contains(';');
  final esc = v.replaceAll('"', '""');
  return needs ? '"$esc"' : esc;
}

/// CSV (UTF-8 BOM — Excel кириллни тўғри очсин). Мижоз маълумоти йўқ.
String smProcurementCsv(SmProcurementReport r, int reservePercent) {
  final rows = <List<String>>[
    ['Бўлим', 'Гуруҳ', 'Нав', 'Таклиф', 'Бирлик', 'Талаб', 'Бўш қолдиқ', 'Жисмоний қолдиқ', 'Етишмайди', 'Захира %', 'Тавсия харид', 'Буюртмалар'],
  ];
  for (final o in r.offers) {
    rows.add([
      o.categoryName,
      o.groupName,
      o.varietyName,
      [o.name, if (o.packLabel != null) o.packLabel!].join(' '),
      smUnitTextRu[o.unit] ?? o.unit,
      _num(o.demandQty),
      o.stock == null ? '' : _num(o.stock!),
      o.onHand == null ? '' : _num(o.onHand!),
      _num(o.shortfall),
      '$reservePercent',
      '${smSuggestedPurchase(shortfall: o.shortfall, demand: o.demandQty, reservePercent: reservePercent)}',
      '${o.orderCount}',
    ]);
  }
  return '﻿${rows.map((r) => r.map(smCsvCell).join(',')).join('\r\n')}\r\n';
}

String smReportQty(num v) => _num(v);

// ─── Аналитика ────────────────────────────────────────────────────────────

class SmTopGroup {
  const SmTopGroup({required this.groupId, required this.sum, required this.lines, this.qty = const {}});
  final String groupId;
  final int sum;
  final int lines;
  final Map<String, num> qty;

  factory SmTopGroup.fromMap(Map m) =>
      SmTopGroup(groupId: '${m['groupId'] ?? ''}', sum: _i(m['sum']), lines: _i(m['lines']), qty: _qtyMap(m['qty']));
}

class SmStatsDay {
  const SmStatsDay({
    required this.date,
    this.orders = 0,
    this.delivered = 0,
    this.cancelled = 0,
    this.open = 0,
    this.gmv = 0,
    this.deliveryFeeRevenue = 0,
    this.courierPayout,
    this.netLogistics,
    this.refundsTotal = 0,
    this.refundsByType = const {},
    this.avgBasket = 0,
    this.uniqueCustomers = 0,
    this.repeatCustomers = 0,
    this.byOrigin = const {},
    this.topGroups = const [],
    this.partial = false,
    this.truncated = false,
    this.courierPayoutPartial = false,
  });

  final String date;
  final int orders;
  final int delivered;
  final int cancelled;
  final int open;
  final int gmv;
  final int deliveryFeeRevenue;
  final int? courierPayout;
  final int? netLogistics;
  final int refundsTotal;
  final Map<String, int> refundsByType;
  final int avgBasket;
  final int uniqueCustomers;
  final int repeatCustomers;
  final Map<String, int> byOrigin;
  final List<SmTopGroup> topGroups;
  final bool partial;
  final bool truncated;

  /// Бирор етказилган буюртмада курьер тўлови нусхаси йўқ → netLogistics null.
  final bool courierPayoutPartial;

  static Map<String, int> _intMap(Object? v) =>
      v is Map ? {for (final e in v.entries) '${e.key}': _i(e.value)} : const {};

  factory SmStatsDay.fromMap(Map m) => SmStatsDay(
        date: '${m['date'] ?? ''}',
        orders: _i(m['orders']),
        delivered: _i(m['delivered']),
        cancelled: _i(m['cancelled']),
        open: _i(m['open']),
        gmv: _i(m['gmv']),
        deliveryFeeRevenue: _i(m['deliveryFeeRevenue']),
        courierPayout: _iN(m['courierPayout']),
        netLogistics: _iN(m['netLogistics']),
        refundsTotal: _i(m['refundsTotal']),
        refundsByType: _intMap(m['refundsByType']),
        avgBasket: _i(m['avgBasket']),
        uniqueCustomers: _i(m['uniqueCustomers']),
        repeatCustomers: _i(m['repeatCustomers']),
        byOrigin: _intMap(m['byOrigin']),
        topGroups: [
          if (m['topGroupsBySum'] is List)
            for (final g in m['topGroupsBySum'] as List)
              if (g is Map) SmTopGroup.fromMap(g),
        ],
        partial: m['partial'] == true,
        truncated: m['truncated'] == true,
        courierPayoutPartial: m['courierPayoutPartial'] == true,
      );
}

class SmStatsReport {
  const SmStatsReport({
    required this.from,
    required this.to,
    required this.days,
    this.missing = const [],
    this.backfilled = const [],
    this.summary = const {},
    this.listsWithReminders,
  });

  final String from;
  final String to;
  final List<SmStatsDay> days;
  final List<String> missing;
  final List<String> backfilled;
  final Map<String, dynamic> summary;
  final int? listsWithReminders;

  factory SmStatsReport.fromMap(Map<String, dynamic> m) {
    List<String> strs(Object? v) => v is List ? [for (final e in v) '$e'] : const [];
    return SmStatsReport(
      from: '${m['from'] ?? ''}',
      to: '${m['to'] ?? ''}',
      days: [
        if (m['days'] is List)
          for (final d in m['days'] as List)
            if (d is Map) SmStatsDay.fromMap(d),
      ],
      missing: strs(m['missing']),
      backfilled: strs(m['backfilled']),
      summary: m['summary'] is Map ? Map<String, dynamic>.from(m['summary'] as Map) : const {},
      listsWithReminders: _iN(m['listsWithReminders']),
    );
  }

  int sumOf(String key) => _i(summary[key]);
  int? get netLogistics => _iN(summary['netLogistics']);
  int? get courierPayout => _iN(summary['courierPayout']);
  bool get courierPayoutPartial => summary['courierPayoutPartial'] == true;

  /// Манба бўйича буюртмалар (тугалланган кунлар бўйича йиғинди).
  Map<String, int> get byOrigin {
    final out = <String, int>{};
    for (final d in days.where((d) => !d.partial)) {
      d.byOrigin.forEach((k, v) => out[k] = (out[k] ?? 0) + v);
    }
    return out;
  }

  /// Энг кўп сотилган гуруҳлар (кунлик топ-20 лардан йиғинди, сумма бўйича).
  List<SmTopGroup> topGroups({int limit = 20}) {
    final by = <String, ({int sum, int lines, Map<String, num> qty})>{};
    for (final d in days.where((d) => !d.partial)) {
      for (final g in d.topGroups) {
        final cur = by[g.groupId];
        final qty = <String, num>{...?cur?.qty};
        g.qty.forEach((k, v) => qty[k] = smFromMilliNum(smReportMilli(qty[k] ?? 0) + smReportMilli(v)));
        by[g.groupId] = (sum: (cur?.sum ?? 0) + g.sum, lines: (cur?.lines ?? 0) + g.lines, qty: qty);
      }
    }
    final list = [
      for (final e in by.entries) SmTopGroup(groupId: e.key, sum: e.value.sum, lines: e.value.lines, qty: e.value.qty),
    ]..sort((a, b) => b.sum != a.sum ? b.sum.compareTo(a.sum) : a.groupId.compareTo(b.groupId));
    return list.take(limit).toList();
  }
}

num smFromMilliNum(int m) => m % 1000 == 0 ? m ~/ 1000 : m / 1000;

/// YYYY-MM-DD (DateTime'нинг йил/ой/кун майдонлари бўйича).
String smDateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Тошкент бўйича бугунги сана (UTC+5; сервер `tashkentParts` билан бир хил) — браузер вақт минтақасидан қатъи назар.
DateTime smTashkentToday([DateTime? nowUtc]) {
  final t = (nowUtc ?? DateTime.now().toUtc()).add(const Duration(hours: 5));
  return DateTime.utc(t.year, t.month, t.day);
}

// ─── Курьер тўлови (эга 2026-11-26) ───────────────────────────────────────
// Тўлов — админ курьер КАРТАСИГА тизимдан ташқарида қўлда ўтказади. Тизим пул юрмайди, карта маълумоти САҚЛАНМАЙДИ.
// Сақланиши (сервер): нусха ва «тўланди» белгиси — orders/{id}/private/courier_payout (фақат админ ўқийди, мижоз
// ўқийдиган буюртма ҳужжатида ЙЎҚ, 14-банд). Бу экран фақат callable'лар орқали ишлайди — шакл ўзгармади.

/// `settings/supermarket.courierPayout`: percent (0..100, буюртма етказиш ҳақидан) ёки fixed (сўм).
class SmCourierPayout {
  const SmCourierPayout.percent(int this.percent)
      : mode = 'percent',
        fixedAmount = null;
  const SmCourierPayout.fixed(int this.fixedAmount)
      : mode = 'fixed',
        percent = null;

  final String mode;
  final int? percent;
  final int? fixedAmount;

  static SmCourierPayout? fromMap(Object? v) {
    if (v is! Map) return null;
    if (v['mode'] == 'percent' && v['percent'] is num) return SmCourierPayout.percent((v['percent'] as num).toInt());
    if (v['mode'] == 'fixed' && v['fixedAmount'] is num) return SmCourierPayout.fixed((v['fixedAmount'] as num).toInt());
    return null;
  }

  Map<String, dynamic> toMap() =>
      mode == 'percent' ? {'mode': 'percent', 'percent': percent} : {'mode': 'fixed', 'fixedAmount': fixedAmount};

  /// Сервер `courierPayoutProblems` кўзгуси.
  List<String> problems() => [
        if (mode == 'percent' && (percent == null || percent! < 0 || percent! > 100)) 'Курьер улуши 0..100%',
        if (mode == 'fixed' && (fixedAmount == null || fixedAmount! < 0)) 'Курьер суммаси 0 ёки ундан катта',
      ];
}

class SmCourierPayoutOrder {
  const SmCourierPayoutOrder({required this.orderId, required this.date, this.deliveryFee = 0, this.amount, this.paid = false});
  final String orderId;
  final String date;
  final int deliveryFee;
  final int? amount;
  final bool paid;

  factory SmCourierPayoutOrder.fromMap(Map m) => SmCourierPayoutOrder(
        orderId: '${m['orderId'] ?? ''}',
        date: '${m['date'] ?? ''}',
        deliveryFee: _i(m['deliveryFee']),
        amount: _iN(m['amount']),
        paid: m['paid'] == true,
      );
}

class SmCourierPayoutGroup {
  const SmCourierPayoutGroup({
    required this.courierId,
    this.name = '',
    this.phone = '',
    this.orders = const [],
    this.total = 0,
    this.paid = 0,
    this.unpaid = 0,
    this.missing = 0,
  });

  final String courierId;
  final String name;
  final String phone;
  final List<SmCourierPayoutOrder> orders;
  final int total;
  final int paid;
  final int unpaid;
  final int missing;

  /// Белгилаш мумкин бўлганлар: сумма бор ва ҳали тўланмаган.
  List<SmCourierPayoutOrder> get payable => [for (final o in orders) if (!o.paid && o.amount != null) o];

  factory SmCourierPayoutGroup.fromMap(Map m) => SmCourierPayoutGroup(
        courierId: '${m['courierId'] ?? ''}',
        name: '${m['name'] ?? ''}',
        phone: '${m['phone'] ?? ''}',
        orders: [
          if (m['orders'] is List)
            for (final o in m['orders'] as List)
              if (o is Map) SmCourierPayoutOrder.fromMap(o),
        ],
        total: _i(m['total']),
        paid: _i(m['paid']),
        unpaid: _i(m['unpaid']),
        missing: _i(m['missing']),
      );
}

class SmCourierPayoutReport {
  const SmCourierPayoutReport({required this.from, required this.to, this.couriers = const [], this.truncated = false});
  final String from;
  final String to;
  final List<SmCourierPayoutGroup> couriers;
  final bool truncated;

  factory SmCourierPayoutReport.fromMap(Map<String, dynamic> m) => SmCourierPayoutReport(
        from: '${m['from'] ?? ''}',
        to: '${m['to'] ?? ''}',
        truncated: m['truncated'] == true,
        couriers: [
          if (m['couriers'] is List)
            for (final c in m['couriers'] as List)
              if (c is Map) SmCourierPayoutGroup.fromMap(c),
        ],
      );
}

/// CSV: курьер (исм, телефон), буюртма, сана, етказиш ҳақи, курьерга, ҳолат. Мижоз маълумоти ва карта йўқ.
String smCourierPayoutCsv(SmCourierPayoutReport r) {
  final rows = <List<String>>[
    ['Курьер', 'Телефон', 'Буюртма', 'Сана', 'Етказиш ҳақи', 'Курьерга', 'Ҳолат'],
  ];
  for (final c in r.couriers) {
    for (final o in c.orders) {
      rows.add([
        c.name,
        c.phone,
        o.orderId,
        o.date,
        '${o.deliveryFee}',
        o.amount == null ? '' : '${o.amount}',
        o.amount == null ? 'белгиланмаган' : (o.paid ? 'тўланган' : 'тўланмаган'),
      ]);
    }
  }
  return '\uFEFF${rows.map((r) => r.map(smCsvCell).join(',')).join('\r\n')}\r\n';
}