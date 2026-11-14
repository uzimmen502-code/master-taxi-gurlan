// Улгуржи — AVA улуши ҳисоботи (эга, 2026-11-14: «ҳар 10 кунда сотувчилардан олинадиган 2%»)
// ва ойлик ҳисобот — СОФ мантиқ (Firestore'сиз, тестланади).
//
//   • 10 кунлик давр: 1–10, 11–20, 21–ой охири (Asia/Tashkent) — сервер `parsePeriod`
//     (`functions_demand/api/wholesale_fee_statement.js`) билан бир хил; давр калити `YYYY-MM-DD`.
//   • `adminGetWholesaleFeeStatement` / `adminGetWholesaleOrdersReport` жавоблари → кўриниш.
//   • CSV матни (нусхалаш учун).
//
// Пул ва «йиғилди» белгиси — фақат СЕРВЕРДА ҳисобланади (18, 41, 44-банд); бу ерда кўрсатиш.

import 'wholesale_orders_admin.dart' show wholesaleMoney, wholesaleTimeOf;

/// Asia/Tashkent = UTC+5, ёзги вақт йўқ (сервер `TASHKENT_OFFSET_MS` билан бир хил).
const Duration kTashkentOffset = Duration(hours: 5);

/// Тўлов усули номлари (сервер `PAYMENT_METHOD`). Номаълум — коднинг ўзи.
const kWholesalePaymentMethodLabels = <String, String>{
  'wallet': 'Ҳамён (олдиндан)',
  'card_on_delivery': 'Карта (етказилганда)',
  'bank_transfer': 'Банк ўтказмаси',
};

String wholesaleMethodLabel(String m) => kWholesalePaymentMethodLabels[m] ?? m;

String _two(int v) => v.toString().padLeft(2, '0');

/// 10 кунлик давр. [day] — 1 | 11 | 21.
class WholesaleFeePeriod {
  WholesaleFeePeriod(this.year, this.month, this.day) {
    if (day != 1 && day != 11 && day != 21) throw ArgumentError.value(day, 'day', '1 | 11 | 21');
    if (month < 1 || month > 12) throw ArgumentError.value(month, 'month');
  }

  final int year;
  final int month;
  final int day;

  /// Сервер калити: `YYYY-MM-DD`.
  String get key => '$year-${_two(month)}-${_two(day)}';

  /// Давр охирги куни (10, 20 ёки ой охири — 28/29/30/31).
  int get lastDay => day == 21 ? DateTime.utc(year, month + 1, 0).day : day + 9;

  /// Давр боши (Тошкент 00:00) — UTC.
  DateTime get startUtc => DateTime.utc(year, month, day).subtract(kTashkentOffset);

  /// Давр охири (ЭКСКЛЮЗИВ, кейинги даврнинг боши) — UTC.
  DateTime get endUtc => next.startUtc;

  WholesaleFeePeriod get next => day == 21
      ? WholesaleFeePeriod(month == 12 ? year + 1 : year, month == 12 ? 1 : month + 1, 1)
      : WholesaleFeePeriod(year, month, day + 10);

  WholesaleFeePeriod get previous => day == 1
      ? WholesaleFeePeriod(month == 1 ? year - 1 : year, month == 1 ? 12 : month - 1, 21)
      : WholesaleFeePeriod(year, month, day - 10);

  /// Давр ёпилганми (сервер ҳам текширади: `period_not_closed`).
  bool isClosedAt(DateTime now) => !now.toUtc().isBefore(endUtc);

  /// «01.11–10.11.2026».
  String get label => '${_two(day)}.${_two(month)}–${_two(lastDay)}.${_two(month)}.$year';

  /// [now] пайтида Тошкентда жорий (ҳали очиқ) давр.
  static WholesaleFeePeriod containing(DateTime now) {
    final l = now.toUtc().add(kTashkentOffset);
    final d = l.day <= 10 ? 1 : (l.day <= 20 ? 11 : 21);
    return WholesaleFeePeriod(l.year, l.month, d);
  }

  /// Стандарт танлов: охирги ЁПИЛГАН давр.
  static WholesaleFeePeriod lastClosed(DateTime now) => containing(now).previous;

  /// Танлов рўйхати: жорий (очиқ) даврдан бошлаб орқага [count] та.
  static List<WholesaleFeePeriod> recent(DateTime now, {int count = 18}) {
    final out = <WholesaleFeePeriod>[];
    var p = containing(now);
    for (var i = 0; i < count; i += 1) {
      out.add(p);
      p = p.previous;
    }
    return out;
  }

  @override
  bool operator ==(Object other) => other is WholesaleFeePeriod && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Ой калити `YYYY-MM` — [now] дан орқага [count] та (биринчиси — жорий ой, Тошкентда).
List<String> wholesaleRecentMonths(DateTime now, {int count = 12}) {
  final l = now.toUtc().add(kTashkentOffset);
  var y = l.year;
  var m = l.month;
  final out = <String>[];
  for (var i = 0; i < count; i += 1) {
    out.add('$y-${_two(m)}');
    m -= 1;
    if (m == 0) {
      m = 12;
      y -= 1;
    }
  }
  return out;
}

/// Телефоннинг охирги 4 рақами («…1234») — жадвалда тўлиқ рақам кўрсатилмайди (40-банд).
String wholesalePhoneTail(String id) {
  final d = id.replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return '—';
  return '…${d.length <= 4 ? d : d.substring(d.length - 4)}';
}

int _int(Object? v) => v is num && v.isFinite ? v.toInt() : 0;
String _str(Object? v) => v is String ? v.trim() : '';

/// «Йиғилди» белгиси (`admin_audit`, сервер ёзади).
class WholesaleFeeCollected {
  const WholesaleFeeCollected({this.at, this.by = '', this.amount});

  final DateTime? at;
  final String by;
  final int? amount;
}

class WholesaleFeeStatementRow {
  const WholesaleFeeStatementRow({
    required this.sellerId,
    required this.count,
    required this.goodsTotal,
    required this.avaFeeDue,
    this.collected,
  });

  final String sellerId;
  final int count;
  final int goodsTotal;

  /// Сотувчидан олинадиган AVA улуши (бутун сўм; муҳрланган `settlement.avaFee` йиғиндиси).
  final int avaFeeDue;
  final WholesaleFeeCollected? collected;

  bool get isCollected => collected != null;
}

/// `adminGetWholesaleFeeStatement` жавоби.
class WholesaleFeeStatement {
  const WholesaleFeeStatement({
    required this.periodStart,
    required this.lastDay,
    required this.closed,
    required this.sellers,
    required this.totalCount,
    required this.totalGoods,
    required this.totalDue,
    required this.anomalies,
    required this.truncated,
  });

  final String periodStart;
  final String lastDay;
  final bool closed;
  final List<WholesaleFeeStatementRow> sellers;
  final int totalCount;
  final int totalGoods;
  final int totalDue;

  /// Муҳри бузилган буюртмалар (суммага ҚЎШИЛМАГАН) — `orderId`лар.
  final List<String> anomalies;
  final bool truncated;

  factory WholesaleFeeStatement.fromMap(Map<String, dynamic> d) {
    final raw = d['sellers'];
    final rows = <WholesaleFeeStatementRow>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final c = e['collected'];
        rows.add(WholesaleFeeStatementRow(
          sellerId: _str(e['sellerId']),
          count: _int(e['count']),
          goodsTotal: _int(e['goodsTotal']),
          avaFeeDue: _int(e['avaFeeDue']),
          collected: c is Map
              ? WholesaleFeeCollected(
                  at: wholesaleTimeOf(c['at']),
                  by: _str(c['by']),
                  amount: c['amount'] is num ? (c['amount'] as num).toInt() : null,
                )
              : null,
        ));
      }
    }
    final t = d['totals'] is Map ? d['totals'] as Map : const {};
    final an = d['anomalies'];
    return WholesaleFeeStatement(
      periodStart: _str(d['periodStart']),
      lastDay: _str(d['lastDay']),
      closed: d['closed'] == true,
      sellers: rows,
      totalCount: _int(t['count']),
      totalGoods: _int(t['goodsTotal']),
      totalDue: _int(t['avaFeeDue']),
      anomalies: an is List ? [for (final a in an) if (a is Map) _str(a['orderId'])] : const [],
      truncated: d['truncated'] == true,
    );
  }
}

class WholesaleMonthlyRow {
  const WholesaleMonthlyRow({
    required this.sellerId,
    required this.paymentMethod,
    required this.count,
    required this.goodsTotal,
    required this.deliveryFee,
    required this.avaFee,
    required this.avaFeeVia,
  });

  final String sellerId;
  final String paymentMethod;
  final int count;
  final int goodsTotal;
  final int deliveryFee;
  final int avaFee;

  /// `release` — етказилганда ledger орқали; `statement` — 10 кунлик ҳисобот орқали.
  final String avaFeeVia;
}

/// `adminGetWholesaleOrdersReport` жавоби.
class WholesaleMonthlyReport {
  const WholesaleMonthlyReport({
    required this.month,
    required this.rows,
    required this.totalCount,
    required this.totalGoods,
    required this.totalDelivery,
    required this.totalAvaFee,
    required this.anomalies,
    required this.truncated,
  });

  final String month;
  final List<WholesaleMonthlyRow> rows;
  final int totalCount;
  final int totalGoods;
  final int totalDelivery;
  final int totalAvaFee;
  final List<String> anomalies;
  final bool truncated;

  factory WholesaleMonthlyReport.fromMap(Map<String, dynamic> d) {
    final raw = d['rows'];
    final t = d['totals'] is Map ? d['totals'] as Map : const {};
    final an = d['anomalies'];
    return WholesaleMonthlyReport(
      month: _str(d['month']),
      rows: [
        if (raw is List)
          for (final e in raw)
            if (e is Map)
              WholesaleMonthlyRow(
                sellerId: _str(e['sellerId']),
                paymentMethod: _str(e['paymentMethod']),
                count: _int(e['count']),
                goodsTotal: _int(e['goodsTotal']),
                deliveryFee: _int(e['deliveryFee']),
                avaFee: _int(e['avaFee']),
                avaFeeVia: _str(e['avaFeeVia']),
              ),
      ],
      totalCount: _int(t['count']),
      totalGoods: _int(t['goodsTotal']),
      totalDelivery: _int(t['deliveryFee']),
      totalAvaFee: _int(t['avaFee']),
      anomalies: an is List ? [for (final a in an) if (a is Map) _str(a['orderId'])] : const [],
      truncated: d['truncated'] == true,
    );
  }
}

String _csvCell(String v) =>
    v.contains(RegExp('[",;\n\r]')) ? '"${v.replaceAll('"', '""')}"' : v;

String _csv(List<List<String>> rows) => rows.map((r) => r.map(_csvCell).join(',')).join('\n');

/// 10 кунлик ҳисобот CSV (пул — бутун сўм, бўшлиқсиз; сотувчи — канон телефон, ички фойдаланиш).
String wholesaleFeeStatementCsv(WholesaleFeeStatement s, {Map<String, String> names = const {}}) => _csv([
      ['period', 'sellerId', 'seller', 'orders', 'goodsTotal', 'avaFeeDue', 'collected'],
      for (final r in s.sellers)
        [
          s.periodStart,
          r.sellerId,
          names[r.sellerId] ?? '',
          '${r.count}',
          '${r.goodsTotal}',
          '${r.avaFeeDue}',
          r.isCollected ? 'yes' : 'no',
        ],
      [s.periodStart, 'TOTAL', '', '${s.totalCount}', '${s.totalGoods}', '${s.totalDue}', ''],
    ]);

/// Ойлик ҳисобот CSV.
String wholesaleMonthlyReportCsv(WholesaleMonthlyReport r, {Map<String, String> names = const {}}) => _csv([
      ['month', 'sellerId', 'seller', 'paymentMethod', 'orders', 'goodsTotal', 'deliveryFee', 'avaFee', 'avaFeeVia'],
      for (final x in r.rows)
        [
          r.month,
          x.sellerId,
          names[x.sellerId] ?? '',
          x.paymentMethod,
          '${x.count}',
          '${x.goodsTotal}',
          '${x.deliveryFee}',
          '${x.avaFee}',
          x.avaFeeVia,
        ],
      [r.month, 'TOTAL', '', '', '${r.totalCount}', '${r.totalGoods}', '${r.totalDelivery}', '${r.totalAvaFee}', ''],
    ]);

/// «12 500 сўм».
String wholesaleSum(int v) => '${wholesaleMoney(v)} сўм';
