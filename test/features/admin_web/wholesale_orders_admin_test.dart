// Ulgurji buyurtma zanjiri, 5-bosqich (admin): viloyatlar matritsasi (simmetriya,
// bo'sh katak yuborilmaydi, payload shakli), AVA ulushi % <-> bps chegaralari,
// darvoza paneli amallari, karta nizosi dialogi (sabab majburiy), buyurtma ko'rinishi.
//
//   flutter test test/features/admin_web/wholesale_orders_admin_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/features/admin_web/services/admin_callable.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_wholesale_orders_service.dart';
import 'package:ava_gurlan/features/admin_web/utils/region_zone_matrix.dart';
import 'package:ava_gurlan/features/admin_web/utils/wholesale_fee_statement.dart';
import 'package:ava_gurlan/features/admin_web/utils/wholesale_orders_admin.dart';
import 'package:ava_gurlan/features/admin_web/widgets/region_zone_matrix_dialog.dart';
import 'package:ava_gurlan/features/admin_web/widgets/wholesale_dispute_dialog.dart';
import 'package:ava_gurlan/features/admin_web/widgets/wholesale_fee_card.dart';
import 'package:ava_gurlan/features/admin_web/widgets/wholesale_fee_statement_panel.dart';
import 'package:ava_gurlan/features/admin_web/widgets/wholesale_stage_panel.dart';

class _Fake implements AdminCallable {
  _Fake(this.handler);

  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>) handler;
  final calls = <(String, Map<String, dynamic>)>[];

  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> payload) {
    calls.add((name, payload));
    return handler(name, payload);
  }
}

const _ids = ['qoraqalpogiston', 'xorazm', 'toshkent_shahri'];
const _regions = [
  MatrixRegion('qoraqalpogiston', 'Қорақалпоғистон'),
  MatrixRegion('xorazm', 'Хоразм'),
  MatrixRegion('toshkent_shahri', 'Тошкент шаҳри'),
];

Map<String, dynamic> _tariff({Object? regions}) => {
      'module': 'logistics',
      'version': 4,
      'currency': 'UZS',
      'volumetricDivisor': 6000,
      'zones': kTariffZones,
      'weightBrackets': [1000, 5000, 20000],
      'prices': {
        'ZONE_1': {'brackets': [10000, 15000, 25000], 'extraPerKg': null},
      },
      'matrix': {
        'regions': regions,
        'districts': {'gurlan': {'urganch': 'ZONE_0'}},
        'symmetric': true,
      },
    };

Future<void> _open(WidgetTester tester, Future<void> Function(BuildContext) show, {Size size = const Size(1400, 1000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(onPressed: () => show(context), child: const Text('open')),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  // ─── Matritsa: sof mantiq ─────────────────────────────────────────────
  group('RegionZoneMatrix', () {
    test('bo\'sh hujjat: hamma katak bo\'sh, payload bo\'sh, saqlash bloklangan (server bo\'sh regions rad etadi)', () {
      final m = RegionZoneMatrix.fromTariff(_ids, null);
      expect(m.totalPairs, 6, reason: '3×3 diagonal bilan = 6');
      expect(m.filledPairs, 0);
      expect(m.emptyPairs, 6);
      expect(m.toRegionsPayload(), isEmpty);
      expect(m.saveBlocker, isNotNull);
      // 14 viloyat — 105 juftlik.
      expect(RegionZoneMatrix.fromTariff(List.generate(14, (i) => 'r$i'), null).totalPairs, 105);
    });

    test('simmetriya: yuqori katak ikkala yo\'nalishda; diagonal bir marta; bo\'sh katak YUBORILMAYDI', () {
      final m = RegionZoneMatrix.fromTariff(_ids, null)
        ..setZone(0, 1, 'ZONE_3')
        ..setZone(2, 2, 'ZONE_0');
      expect(m.zoneAt(1, 0), 'ZONE_3', reason: 'pastki — ko\'zgu');
      expect(m.zoneAt(0, 2), isNull);
      final p = m.toRegionsPayload();
      expect(p, {
        'qoraqalpogiston': {'xorazm': 'ZONE_3'},
        'xorazm': {'qoraqalpogiston': 'ZONE_3'},
        'toshkent_shahri': {'toshkent_shahri': 'ZONE_0'},
      });
      for (final row in p.values) {
        expect(row.values.every((z) => z is String && kTariffZones.contains(z)), isTrue, reason: 'null/bo\'sh yo\'q');
      }
      expect(m.filledPairs, 2);
      expect(m.emptyPairs, 4);
      // Tozalash — juftlik payload'dan chiqadi (bo'sh qator ham qolmaydi).
      m.setZone(1, 0, null);
      expect(m.toRegionsPayload(), {'toshkent_shahri': {'toshkent_shahri': 'ZONE_0'}});
      expect(() => m.setZone(0, 1, 'Z1'), throwsArgumentError, reason: 'eski Z1..Z5 modeli yo\'q');
    });

    test('mavjud hujjat: bir yo\'nalishli juftlik ko\'zguda; jadvaldan tashqari ID o\'zgarishsiz saqlanadi', () {
      final m = RegionZoneMatrix.fromTariff(_ids, {
        'toshkent_shahri': {'xorazm': 'ZONE_4'},
        'samarqand': {'xorazm': 'ZONE_2'},
        'xorazm': {'navoiy': 'ZONE_3'},
      });
      expect(m.zoneAt(1, 2), 'ZONE_4');
      expect(m.zoneAt(2, 1), 'ZONE_4');
      expect(m.foreignPairCount, 2);
      expect(m.toRegionsPayload(), {
        'samarqand': {'xorazm': 'ZONE_2'},
        'xorazm': {'navoiy': 'ZONE_3', 'toshkent_shahri': 'ZONE_4'},
        'toshkent_shahri': {'xorazm': 'ZONE_4'},
      });
    });

    test('ziddiyat (a→b ≠ b→a) — saqlash bloklanadi, admin katakni tanlagach ochiladi', () {
      final m = RegionZoneMatrix.fromTariff(_ids, {
        'qoraqalpogiston': {'xorazm': 'ZONE_1'},
        'xorazm': {'qoraqalpogiston': 'ZONE_2'},
      });
      expect(m.isConflict(0, 1), isTrue);
      expect(m.zoneAt(0, 1), 'ZONE_1', reason: 'yuqori uchburchak yo\'nalishi ko\'rsatiladi');
      expect(m.saveBlocker, contains('ҳар хил'));
      m.setZone(0, 1, 'ZONE_2');
      expect(m.hasConflicts, isFalse);
      expect(m.saveBlocker, isNull);
      expect(m.toRegionsPayload()['qoraqalpogiston'], {'xorazm': 'ZONE_2'});
    });

    test('noto\'g\'ri qiymat bo\'sh deb olinadi va belgilanadi; applyToTariff boshqa maydonlarni saqlaydi', () {
      final m = RegionZoneMatrix.fromTariff(_ids, {
        'xorazm': {'xorazm': 'Z1', 'qoraqalpogiston': 'ZONE_1'},
      });
      expect(m.zoneAt(1, 1), isNull);
      expect(m.isInvalid(1, 1), isTrue);
      final doc = m.applyToTariff(_tariff(regions: const {}));
      expect(doc['version'], 4);
      expect(doc['prices'], isNotNull);
      final matrix = doc['matrix'] as Map;
      expect(matrix['districts'], {'gurlan': {'urganch': 'ZONE_0'}}, reason: 'districts tegilmaydi');
      expect(matrix['symmetric'], true);
      expect(matrix['regions'], {
        'xorazm': {'qoraqalpogiston': 'ZONE_1'},
        'qoraqalpogiston': {'xorazm': 'ZONE_1'},
      });
    });
  });

  // ─── Matritsa: dialog ─────────────────────────────────────────────────
  testWidgets('Matritsa dialogi: yuqori katak tanlanadi, pastki ko\'zguda; saqlash payload\'i aniq shakl', (tester) async {
    Map<String, dynamic>? out;
    await _open(tester, (c) async {
      out = await showDialog<Map<String, dynamic>>(
        context: c,
        builder: (_) => RegionZoneMatrixDialog(tariff: _tariff(regions: null), version: 4, regions: _regions),
      );
    });
    expect(find.textContaining('Тўлдирилган: 0 / 6'), findsOneWidget);
    expect(find.byKey(const ValueKey('matrix-blocker')), findsOneWidget, reason: 'bo\'sh matritsa saqlanmaydi');
    expect(find.byKey(const ValueKey('zcell-1-0')), findsNothing, reason: 'pastki uchburchak tahrirlanmaydi');

    await tester.tap(find.byKey(const ValueKey('zcell-0-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ZONE_3').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Тўлдирилган: 1 / 6'), findsOneWidget);
    expect(find.text('Z3'), findsNWidgets(2), reason: 'yuqori + ko\'zgu');
    expect(find.byKey(const ValueKey('matrix-blocker')), findsNothing);

    await tester.tap(find.text('Матрицани сақлаш'));
    await tester.pumpAndSettle();
    expect(out, isNotNull);
    final matrix = out!['matrix'] as Map;
    expect(matrix['regions'], {
      'qoraqalpogiston': {'toshkent_shahri': 'ZONE_3'},
      'toshkent_shahri': {'qoraqalpogiston': 'ZONE_3'},
    });
    expect(matrix['districts'], {'gurlan': {'urganch': 'ZONE_0'}});
    expect(out!['version'], 4);
    expect(out!['weightBrackets'], [1000, 5000, 20000], reason: 'tarifning qolgani o\'zgarmaydi');
  });

  testWidgets('Matritsa: katakni «бўш»ga qaytarish — juftlik yuborilmaydi', (tester) async {
    Map<String, dynamic>? out;
    await _open(tester, (c) async {
      out = await showDialog<Map<String, dynamic>>(
        context: c,
        builder: (_) => RegionZoneMatrixDialog(
          tariff: _tariff(regions: {
            'xorazm': {'xorazm': 'ZONE_0', 'toshkent_shahri': 'ZONE_4'},
          }),
          version: 4,
          regions: _regions,
        ),
      );
    });
    expect(find.textContaining('Тўлдирилган: 2 / 6'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('zcell-1-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('— бўш (нарх йўқ)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Матрицани сақлаш'));
    await tester.pumpAndSettle();
    expect((out!['matrix'] as Map)['regions'], {'xorazm': {'xorazm': 'ZONE_0'}});
  });

  // ─── AVA ulushi ───────────────────────────────────────────────────────
  group('AVA ulushi % ↔ bps', () {
    test('chegaralar 0..30 %, 2 o\'nli xonagacha, vergul ham', () {
      expect(wholesaleFeePercentToBps('0'), 0);
      expect(wholesaleFeePercentToBps('30'), 3000);
      expect(wholesaleFeePercentToBps('30.00'), 3000);
      expect(wholesaleFeePercentToBps('30.01'), isNull);
      expect(wholesaleFeePercentToBps('31'), isNull);
      expect(wholesaleFeePercentToBps('2,5'), 250);
      expect(wholesaleFeePercentToBps('12.75'), 1275);
      expect(wholesaleFeePercentToBps('0.01'), 1);
      expect(wholesaleFeePercentToBps('2.555'), isNull, reason: 'yaxlitlanmaydi');
      expect(wholesaleFeePercentToBps('-1'), isNull);
      expect(wholesaleFeePercentToBps(''), isNull);
      expect(wholesaleFeePercentToBps('abc'), isNull);
      expect(wholesaleFeeBpsToPercent(250), '2.5');
      expect(wholesaleFeeBpsToPercent(3000), '30');
      expect(wholesaleFeeBpsToPercent(1), '0.01');
    });

    test('reja: o\'zgarmagan / hujjat yo\'q (0 % ham yangi yozuv)', () {
      const cur = WholesaleFeeCurrent(avaFeeBps: 250, feeVersion: 3, exists: true);
      expect(planWholesaleFee('2.5', cur).unchanged, isTrue);
      expect(planWholesaleFee('3', cur).bps, 300);
      expect(planWholesaleFee('40', cur).error, isNotNull);
      final none = planWholesaleFee('0', const WholesaleFeeCurrent());
      expect([none.bps, none.unchanged], [0, false], reason: 'hujjat yo\'q — server birinchi versiyani yozadi');
    });
  });

  testWidgets('AVA ulushi kartasi: 31 % — xato, server chaqirilmaydi; 2,5 % — sabab bilan 250 bps yuboriladi', (tester) async {
    final demand = _Fake((n, p) async => {'ok': true, 'unchanged': false, 'avaFeeBps': p['avaFeeBps'], 'feeVersion': 4});
    final svc = AdminWholesaleOrdersService(demand: demand);
    var doc = <String, dynamic>{'avaFeeBps': 200, 'feeVersion': 3};
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WholesaleFeeCard(svc: svc, loader: () async => doc))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ҳозир: 2 % (200 bps) · v3'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '31');
    await tester.tap(find.text('Сақлаш'));
    await tester.pumpAndSettle();
    expect(demand.calls, isEmpty);
    expect(find.textContaining('0..30 %'), findsWidgets);

    await tester.enterText(find.byType(TextField), '2,5');
    await tester.tap(find.text('Сақлаш'));
    await tester.pumpAndSettle();
    expect(find.text('Тасдиқлаш'), findsOneWidget, reason: 'sabab dialogi');
    await tester.enterText(find.byType(TextField).last, 'ega qarori');
    await tester.pump();
    doc = {'avaFeeBps': 250, 'feeVersion': 4};
    await tester.tap(find.text('Тасдиқлаш'));
    await tester.pumpAndSettle();
    expect(demand.calls.single.$1, 'setWholesaleOrderSettings');
    expect(demand.calls.single.$2, {'avaFeeBps': 250, 'reason': 'ega qarori'});
    expect(demand.calls.single.$2['avaFeeBps'], isA<int>());
    expect(find.textContaining('v4'), findsWidgets);
  });

  // ─── Darvoza ──────────────────────────────────────────────────────────
  testWidgets('Darvoza paneli: ogohlantirish; yoqish/tester qo\'shish/olish — sabab bilan, faqat berilgan maydonlar', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var state = <String, dynamic>{
      'exists': false, 'enabled': false, 'stage': 'internal', 'testerIds': <String>['998901110011'],
      'globalEnabled': true, 'effectiveOpen': false,
    };
    final demand = _Fake((n, p) async {
      if (n == 'adminGetWholesaleOrdersStage') return state;
      return {'ok': true, 'unchanged': false, 'created': true, 'enabled': p['enabled'] ?? false, 'stage': 'internal',
        'testerCount': 1, 'added': 0, 'removed': 0};
    });
    final svc = AdminWholesaleOrdersService(demand: demand);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WholesaleStagePanel(svc: svc))));
    await tester.pumpAndSettle();
    expect(find.text(kWholesaleGateWarning), findsOneWidget);
    expect(find.text('Ҳозир ЁПИҚ'), findsOneWidget);
    expect(demand.calls.single.$1, 'adminGetWholesaleOrdersStage');

    // Yoqish: sabab majburiy (3 belgidan kam — tasdiq tugmasi o'chiq).
    await tester.tap(find.byKey(const ValueKey('wholesale-gate-enabled')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ДИҚҚАТ'), findsNWidgets(2), reason: 'dialogda ham ogohlantirish');
    await tester.enterText(find.byType(TextField).last, 'ab');
    await tester.pump();
    final confirm = find.widgetWithText(FilledButton, 'Тасдиқлаш');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byType(TextField).last, 'ichki sinov');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    final set1 = demand.calls.where((c) => c.$1 == 'adminSetWholesaleOrdersStage').toList();
    expect(set1.single.$2, {'enabled': true, 'reason': 'ichki sinov'});

    // Tester qo'shish: noto'g'ri raqam — chaqiruv yo'q.
    await tester.enterText(find.byKey(const ValueKey('wholesale-tester-phone')), '123');
    await tester.tap(find.text('Қўшиш'));
    await tester.pumpAndSettle();
    expect(demand.calls.where((c) => c.$1 == 'adminSetWholesaleOrdersStage').length, 1);

    await tester.enterText(find.byKey(const ValueKey('wholesale-tester-phone')), '90 222 00 22');
    await tester.tap(find.text('Қўшиш'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'tester');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Тасдиқлаш'));
    await tester.pumpAndSettle();
    var sets = demand.calls.where((c) => c.$1 == 'adminSetWholesaleOrdersStage').toList();
    expect(sets.last.$2, {'addTesterIds': ['902220022'], 'reason': 'tester'});

    // Olish (chip o'chirish).
    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'kerak emas');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Тасдиқлаш'));
    await tester.pumpAndSettle();
    sets = demand.calls.where((c) => c.$1 == 'adminSetWholesaleOrdersStage').toList();
    expect(sets.last.$2, {'removeTesterIds': ['998901110011'], 'reason': 'kerak emas'});

    // Bosqich: PUBLIC tanlash → saqlash.
    state = {...state, 'exists': true};
    await tester.tap(find.byKey(const ValueKey('wholesale-gate-stage')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(kWholesaleStageLabels['public']!).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Босқични сақлаш'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'ega qarori');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Тасдиқлаш'));
    await tester.pumpAndSettle();
    sets = demand.calls.where((c) => c.$1 == 'adminSetWholesaleOrdersStage').toList();
    expect(sets.last.$2, {'stage': 'public', 'reason': 'ega qarori'});
  });

  // ─── Karta nizosi ─────────────────────────────────────────────────────
  testWidgets('Nizo dialogi: sababsiz tugmalar o\'chiq; tasdiq → aniq payload; server xatosi dialogda', (tester) async {
    var fail = true;
    final demand = _Fake((n, p) async {
      if (fail) throw const AdminCallableException('failed-precondition', 'order_not_disputed', 'Holat mos emas');
      return {'ok': true, 'status': 'in_delivery'};
    });
    final svc = AdminWholesaleOrdersService(demand: demand);
    final order = WholesaleOrderAdminView.fromMap('ORD1', {
      'status': 'payment_dispute',
      'paymentMethod': 'card_on_delivery',
      'productTitle': 'Гуруч',
      'goodsTotal': 140000,
      'deliveryFee': 25000,
      'total': 165000,
      'cardPayment': {'status': 'disputed', 'receiptPath': 'wholesale_receipts/ORD1/r.jpg'},
    });
    final asked = <String>[];
    Map<String, dynamic>? res;
    await _open(tester, (c) async {
      res = await showWholesaleDisputeDialog(c, svc: svc, order: order, receiptUrl: (p) async {
        asked.add(p);
        throw Exception('storage denied');
      });
    });
    expect(asked, ['wholesale_receipts/ORD1/r.jpg']);
    expect(find.textContaining('Чек расми очилмади'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Тўловни тасдиқлаш')).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Рад этиш')).onPressed, isNull);

    await tester.enterText(find.byKey(const ValueKey('dispute-reason')), 'ok');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Тўловни тасдиқлаш')).onPressed, isNull,
        reason: '3 belgidan kam');

    await tester.enterText(find.byKey(const ValueKey('dispute-reason')), 'chek bankda bor');
    await tester.pump();
    await tester.tap(find.text('Тўловни тасдиқлаш'));
    await tester.pumpAndSettle();
    expect(demand.calls.single.$1, 'adminResolveWholesaleCardDispute');
    expect(demand.calls.single.$2, {'orderId': 'ORD1', 'decision': 'confirm', 'reason': 'chek bankda bor'});
    expect(find.byKey(const ValueKey('dispute-error')), findsOneWidget, reason: 'xato dialogda, yopilmaydi');
    expect(res, isNull);

    fail = false;
    await tester.tap(find.text('Рад этиш'));
    await tester.pumpAndSettle();
    expect(demand.calls.last.$2['decision'], 'reject');
    expect(find.byType(AlertDialog), findsNothing);
    expect(res, {'ok': true, 'status': 'in_delivery'});
  });

  test('Servis: noto\'g\'ri qaror serverga bormaydi', () {
    final demand = _Fake((n, p) async => {});
    final svc = AdminWholesaleOrdersService(demand: demand);
    expect(() => svc.resolveCardDispute(orderId: 'o', decision: 'approve', reason: 'xxx'), throwsArgumentError);
    expect(demand.calls, isEmpty);
  });

  // ─── Buyurtma ko'rinishi ──────────────────────────────────────────────
  test('Buyurtma: muammolar (anomaliya, yakuniy jo\'natma xatosi, nizo, qaytarish qarzi) va filtr', () {
    final ok = WholesaleOrderAdminView.fromMap('a', {
      'status': 'in_delivery', 'total': 100, 'shipmentError': {'code': 'x', 'attempts': 2, 'final': false},
    });
    expect(ok.hasProblem, isFalse, reason: 'qayta urinilayotgan xato hali muammo emas');
    expect(ok.paymentMethod, 'wallet', reason: 'yo\'q = hamyon');
    expect(ok.matchesFilter(''), isTrue);
    expect(ok.matchesFilter('in_delivery'), isTrue);
    expect(ok.matchesFilter('problem'), isFalse);

    final bad = WholesaleOrderAdminView.fromMap('b', {
      'status': 'payment_dispute',
      'paymentMethod': 'card_on_delivery',
      'shipFundAnomaly': {'code': 'fee_invalid'},
      'releaseAnomaly': {'code': 'escrow_short'},
      'shipmentError': {'code': 'zone_not_found', 'attempts': 5, 'final': true},
      'returnDebt': {'amount': 30000},
      'shipment': {'shipmentId': 'S1', 'trackingNumber': 'AVA-1'},
    });
    expect(bad.problems.map((p) => p.kind).toList(), ['ship_fund', 'release', 'shipment', 'dispute', 'return_debt']);
    expect(bad.problems.last.text, contains('30 000'));
    expect(bad.isCard, isTrue);
    expect(bad.trackingNumber, 'AVA-1');
    expect(bad.matchesFilter('problem'), isTrue);
    expect(bad.matchesFilter('payment_dispute'), isTrue);
    expect(bad.matchesFilter('delivered'), isFalse);
    expect(WholesaleOrderAdminView.fromMap('c', {'status': 'returned', 'returnDebt': {'amount': 0}}).hasProblem, isFalse);
    expect(wholesaleMoney(1234567), '1 234 567');
  });

  // ─── AVA ulushi hisoboti (bank o'tkazmasi, ega 2026-11-14) ─────────────
  group('10 kunlik davr (Asia/Tashkent)', () {
    test('1–10 / 11–20 / 21–oy oxiri: 31, 30, 28 va 29 kunlik oylar', () {
      expect(WholesaleFeePeriod(2026, 11, 1).lastDay, 10);
      expect(WholesaleFeePeriod(2026, 11, 11).lastDay, 20);
      expect(WholesaleFeePeriod(2026, 11, 21).lastDay, 30);
      expect(WholesaleFeePeriod(2026, 12, 21).lastDay, 31);
      expect(WholesaleFeePeriod(2026, 2, 21).lastDay, 28);
      expect(WholesaleFeePeriod(2028, 2, 21).lastDay, 29, reason: 'kabisa yili');
      expect(WholesaleFeePeriod(2026, 2, 21).label, '21.02–28.02.2026');
      expect(WholesaleFeePeriod(2026, 11, 1).key, '2026-11-01');
      expect(() => WholesaleFeePeriod(2026, 11, 5), throwsArgumentError, reason: 'server faqat 01/11/21');
    });

    test('keyingi/oldingi: oy va yil chegarasi; oxiri = keyingi davr boshi (Toshkent 00:00 = 19:00Z)', () {
      expect(WholesaleFeePeriod(2026, 12, 21).next.key, '2027-01-01');
      expect(WholesaleFeePeriod(2027, 1, 1).previous.key, '2026-12-21');
      expect(WholesaleFeePeriod(2026, 3, 1).previous.key, '2026-02-21');
      expect(WholesaleFeePeriod(2026, 11, 11).previous.key, '2026-11-01');
      expect(WholesaleFeePeriod(2026, 11, 1).startUtc, DateTime.utc(2026, 10, 31, 19));
      expect(WholesaleFeePeriod(2026, 2, 21).endUtc, DateTime.utc(2026, 2, 28, 19));
    });

    test('joriy va oxirgi yopilgan davr — Toshkent vaqti bo\'yicha (UTC kechasi boshqa kun)', () {
      // 2026-11-10 19:30Z = Toshkentda 11-noyabr 00:30 → joriy 11–20, yopilgan 1–10.
      final t = DateTime.utc(2026, 11, 10, 19, 30);
      expect(WholesaleFeePeriod.containing(t).key, '2026-11-11');
      expect(WholesaleFeePeriod.lastClosed(t).key, '2026-11-01');
      // 18:59Z = Toshkentda hali 10-noyabr 23:59 → 1–10 hali ochiq.
      final edge = DateTime.utc(2026, 11, 10, 18, 59);
      expect(WholesaleFeePeriod.containing(edge).key, '2026-11-01');
      expect(WholesaleFeePeriod(2026, 11, 1).isClosedAt(edge), isFalse);
      expect(WholesaleFeePeriod(2026, 11, 1).isClosedAt(DateTime.utc(2026, 11, 10, 19)), isTrue, reason: 'chegara — yopiq');
      // 1-mart (fevral 21–28 yopilgan).
      expect(WholesaleFeePeriod.lastClosed(DateTime.utc(2026, 3, 1, 6)).key, '2026-02-21');
      final list = WholesaleFeePeriod.recent(t, count: 4).map((p) => p.key).toList();
      expect(list, ['2026-11-11', '2026-11-01', '2026-10-21', '2026-10-11']);
      expect(wholesaleRecentMonths(DateTime.utc(2026, 1, 15), count: 3), ['2026-01', '2025-12', '2025-11']);
      expect(wholesalePhoneTail('998901234567'), '…4567');
      expect(wholesalePhoneTail(''), '—');
    });

    test('javob o\'qish + CSV (pul butun so\'m, qo\'shtirnoq qochiriladi)', () {
      final s = WholesaleFeeStatement.fromMap({
        'periodStart': '2026-11-01', 'lastDay': '2026-11-10', 'closed': true,
        'sellers': [
          {'sellerId': '998901234567', 'count': 2, 'goodsTotal': 1000000, 'avaFeeDue': 20000,
            'collected': {'at': 1763000000000, 'by': '998900000009', 'amount': 20000}},
          {'sellerId': '998907654321', 'count': 1, 'goodsTotal': 500000, 'avaFeeDue': 10000, 'collected': null},
        ],
        'totals': {'sellers': 2, 'count': 3, 'goodsTotal': 1500000, 'avaFeeDue': 30000},
        'anomalies': [{'orderId': 'bad1', 'code': 'settlement_invalid'}],
        'truncated': false,
      });
      expect(s.sellers.first.isCollected, isTrue);
      expect(s.sellers.first.collected!.at, isNotNull);
      expect(s.sellers.last.isCollected, isFalse);
      expect([s.totalCount, s.totalGoods, s.totalDue], [3, 1500000, 30000]);
      expect(s.anomalies, ['bad1']);
      final csv = wholesaleFeeStatementCsv(s, names: {'998901234567': 'Ali "Savdo", MChJ'});
      final lines = csv.split('\n');
      expect(lines.first, 'period,sellerId,seller,orders,goodsTotal,avaFeeDue,collected');
      expect(lines[1], '2026-11-01,998901234567,"Ali ""Savdo"", MChJ",2,1000000,20000,yes');
      expect(lines.last, '2026-11-01,TOTAL,,3,1500000,30000,');
    });
  });

  Map<String, dynamic> statementReply({bool closed = true, String period = '2026-11-01'}) => {
        'ok': true, 'periodStart': period, 'periodEnd': '2026-11-11', 'lastDay': '2026-11-10', 'closed': closed,
        'methods': ['bank_transfer'],
        'sellers': [
          {'sellerId': '998901234567', 'count': 2, 'goodsTotal': 1000000, 'avaFeeDue': 20000, 'collected': null},
          {'sellerId': '998907654321', 'count': 1, 'goodsTotal': 500000, 'avaFeeDue': 10000,
            'collected': {'at': 1763000000000, 'by': 'adm', 'amount': 10000}},
        ],
        'totals': {'sellers': 2, 'count': 3, 'goodsTotal': 1500000, 'avaFeeDue': 30000},
        'anomalies': [], 'truncated': false,
      };

  testWidgets('2% hisoboti: standart — oxirgi yopilgan davr; jadval, jami; «Yig\'ildi» → tasdiq → server, qayta yuklash',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final demand = _Fake((n, p) async {
      if (n == 'adminGetWholesaleFeeStatement') return statementReply();
      return {'ok': true, 'idempotent': false, 'periodStart': p['periodStart'], 'avaFeeDue': 20000};
    });
    final svc = AdminWholesaleOrdersService(demand: demand);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WholesaleFeeStatementPanel(
          svc: svc,
          now: () => DateTime.utc(2026, 11, 14, 7),
          sellerNames: (ids) async => {'998901234567': 'Ali Savdo'},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(demand.calls.single.$1, 'adminGetWholesaleFeeStatement');
    expect(demand.calls.single.$2, {'periodStart': '2026-11-01'}, reason: '14-noyabr → yopilgan 1–10');
    expect(find.text('Ali Savdo · …4567'), findsOneWidget);
    expect(find.text('…4321'), findsOneWidget, reason: 'nomi yo\'q — telefon oxiri');
    expect(find.text('30 000 сўм'), findsOneWidget, reason: 'jami ulush');
    expect(find.text('✓ йиғилган'), findsOneWidget);
    expect(find.byKey(const ValueKey('fee-mark-998907654321')), findsNothing, reason: 'yig\'ilgan — tugma yo\'q');

    await tester.tap(find.byKey(const ValueKey('fee-mark-998901234567')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'naqd olindi');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Тасдиқлаш'));
    await tester.pumpAndSettle();
    final mark = demand.calls.where((c) => c.$1 == 'adminMarkWholesaleFeeCollected').single;
    expect(mark.$2, {'sellerId': '998901234567', 'periodStart': '2026-11-01', 'note': 'naqd olindi'});
    expect(mark.$2.containsKey('avaFeeDue'), isFalse, reason: 'summa klientdan yuborilmaydi');
    expect(demand.calls.where((c) => c.$1 == 'adminGetWholesaleFeeStatement').length, 2, reason: 'qayta yuklash');

    // CSV — vaqtinchalik bufer (platforma kanali tutiladi).
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.tap(find.byKey(const ValueKey('fee-csv')));
    await tester.pumpAndSettle();
    expect(copied.single, startsWith('period,sellerId,seller,orders,goodsTotal,avaFeeDue,collected\n'));
    expect(copied.single, contains('2026-11-01,998901234567,Ali Savdo,2,1000000,20000,no'));
  });

  testWidgets('2% hisoboti: ochiq davr — «Yig\'ildi» o\'chiq; server xatosi matni', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var fail = false;
    final demand = _Fake((n, p) async {
      if (fail) throw const AdminCallableException('permission-denied', '', 'denied');
      return statementReply(closed: false, period: '2026-11-11');
    });
    final svc = AdminWholesaleOrdersService(demand: demand);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WholesaleFeeStatementPanel(svc: svc, now: () => DateTime.utc(2026, 11, 14, 7), sellerNames: (_) async => {}),
      ),
    ));
    await tester.pumpAndSettle();
    // Ochiq davrni tanlash.
    await tester.tap(find.byKey(const ValueKey('fee-period')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('11.11–20.11.2026 (очиқ)').last);
    await tester.pumpAndSettle();
    expect(demand.calls.last.$2, {'periodStart': '2026-11-11'});
    expect(find.byKey(const ValueKey('fee-open-period')), findsOneWidget);
    final btn = tester.widget<FilledButton>(find.byKey(const ValueKey('fee-mark-998901234567')));
    expect(btn.onPressed, isNull, reason: 'server period_not_closed — tugma o\'chiq');

    fail = true;
    await tester.tap(find.byTooltip('Янгилаш'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fee-error')), findsOneWidget);
    expect(find.textContaining('Рухсат йўқ'), findsOneWidget);
  });

  testWidgets('Oylik hisobot: standart — o\'tgan oy; sotuvchi × usul jadvali', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final demand = _Fake((n, p) async => {
          'ok': true, 'month': p['month'], 'timezone': 'Asia/Tashkent',
          'rows': [
            {'sellerId': '998901234567', 'paymentMethod': 'bank_transfer', 'count': 2, 'goodsTotal': 1000000,
              'deliveryFee': 90000, 'avaFee': 20000, 'avaFeeVia': 'statement'},
            {'sellerId': '998901234567', 'paymentMethod': 'wallet', 'count': 1, 'goodsTotal': 300000,
              'deliveryFee': 40000, 'avaFee': 6000, 'avaFeeVia': 'release'},
          ],
          'byMethod': {},
          'totals': {'count': 3, 'goodsTotal': 1300000, 'deliveryFee': 130000, 'avaFee': 26000},
          'anomalies': [], 'truncated': false,
        });
    final svc = AdminWholesaleOrdersService(demand: demand);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WholesaleMonthlyReportPanel(svc: svc, now: () => DateTime.utc(2026, 1, 5), sellerNames: (_) async => {}),
      ),
    ));
    await tester.pumpAndSettle();
    expect(demand.calls.single.$1, 'adminGetWholesaleOrdersReport');
    expect(demand.calls.single.$2, {'month': '2025-12'}, reason: 'yanvar → o\'tgan oy dekabr (yil chegarasi)');
    expect(find.text('Банк ўтказмаси'), findsOneWidget);
    expect(find.text('Ҳамён (олдиндан)'), findsOneWidget);
    expect(find.text('ҳисобот'), findsOneWidget);
    expect(find.text('ledger'), findsOneWidget);
    expect(find.text('26 000 сўм'), findsOneWidget);
  });

  test('Buyurtma ko\'rinishi: bank_transfer saqlanadi (hamyonga aylanmaydi), bankPayment o\'qiladi', () {
    final o = WholesaleOrderAdminView.fromMap('b1', {
      'status': 'placed', 'paymentMethod': 'bank_transfer', 'bankPayment': {'status': 'awaiting'},
    });
    expect(o.isBank, isTrue);
    expect(o.isCard, isFalse);
    expect(o.bankPayment, {'status': 'awaiting'});
    expect(WholesaleOrderAdminView.fromMap('x', {'paymentMethod': 'weird'}).paymentMethod, 'wallet');
  });

  test('Darvoza holati: noma\'lum bosqich — internal; javobdan o\'qish', () {
    final s = WholesaleGateState.fromMap({
      'exists': true, 'enabled': true, 'stage': 'beta', 'testerIds': ['998901110011'], 'effectiveOpen': true,
      'updatedAtMs': 1761912000000,
    });
    expect(s.stage, 'internal');
    expect(s.globalEnabled, isTrue);
    expect(s.testerIds, ['998901110011']);
    expect(s.updatedAt, isNotNull);
  });
}
