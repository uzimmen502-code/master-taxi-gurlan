import 'dart:convert';
import 'dart:typed_data';

import 'package:ava_gurlan/features/admin_web/screens/supermarket_admin_screen.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_supermarket_service.dart';
import 'package:ava_gurlan/features/supermarket/data/supermarket_repository.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_cart.dart';
import 'package:ava_gurlan/features/supermarket/supermarket_controller.dart';
import 'package:ava_gurlan/core/utils/formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../supermarket/sm_fixture.dart';

Map<String, String> _n(String s) => {'uz_Cyrl': s, 'uz_Latn': '$s-lat', 'ru': '$s-ru'};

final _proc = <String, dynamic>{
  'ok': true,
  'date': '2026-11-22',
  'orderCount': 3,
  'truncated': false,
  'stockIsNetOfReservations': true,
  'offers': [
    {
      'productId': 'pot1', 'name': 'Картошка', 'groupId': 'potato', 'groupNames': _n('Картошка'), 'categoryId': 'veg',
      'categoryNames': _n('Сабзавотлар'), 'varietyId': 'local', 'varietyNames': _n('Маҳаллий'), 'unit': 'kg', 'weighed': true,
      'demandQty': 12.5, 'stock': 0, 'reserved': 10, 'onHand': 10, 'shortfall': 2.5, 'orderCount': 3,
    },
    {
      'productId': 'milk1', 'name': 'Сут 1 л', 'packLabel': '1 л', 'groupId': 'milk', 'groupNames': _n('Сут'), 'categoryId': 'dairy',
      'categoryNames': _n('Сут маҳсулотлари'), 'unit': 'l', 'demandQty': 4, 'stock': 16, 'reserved': 4, 'onHand': 20, 'shortfall': 0, 'orderCount': 2,
    },
  ],
};

Map<String, dynamic> _day(String date, {int? net, bool partial = false}) => {
      'date': date, 'orders': 4, 'delivered': 3, 'cancelled': 1, 'open': 0, 'gmv': 120000, 'deliveryFeeRevenue': 12000,
      'courierPayout': net == null ? null : 12000 - net, 'netLogistics': net, 'refundsTotal': 3000, 'avgBasket': 40000,
      'uniqueCustomers': 3, 'repeatCustomers': 1,
      'byOrigin': {'catalog': 2, 'quick': 0, 'weekly': 1, 'reorder': 1, 'unknown': 0},
      'topGroupsBySum': [
        {'groupId': 'beef', 'sum': 80000, 'lines': 2, 'qty': {'kg': 1.5}},
        {'groupId': 'potato', 'sum': 20000, 'lines': 3, 'qty': {'kg': 4}},
      ],
      if (partial) 'partial': true,
    };

final _payouts = <String, dynamic>{
  'couriers': [
    {
      'courierId': '998931112233', 'name': 'Бек', 'phone': '998931112233', 'total': 6156, 'paid': 156, 'unpaid': 6000, 'missing': 1,
      'orders': [
        {'orderId': 'o5', 'date': '2026-11-20', 'deliveryFee': 1200, 'amount': 156, 'paid': true},
        {'orderId': 'o6', 'date': '2026-11-20', 'deliveryFee': 1200, 'amount': 6000, 'paid': false},
        {'orderId': 'o2', 'date': '2026-11-20', 'deliveryFee': 1100, 'amount': null, 'paid': false},
      ],
    },
  ],
};
class _Fake extends AdminSupermarketService {
  final procDates = <String>[];
  final statsCalls = <({String from, String to, bool backfill})>[];
  Object? procError;
  Map<String, dynamic> statsResult = {};

  @override
  Future<Map<String, dynamic>?> loadTaxonomyRaw() async => {
        'categories': [
          {'id': 'meat', 'groups': [{'id': 'beef', 'names': _n('Мол гўшти')}]},
        ],
      };

  @override
  Future<SmProcurementReport> procurementReport(String date) async {
    procDates.add(date);
    if (procError != null) throw procError!;
    return SmProcurementReport.fromMap({..._proc, 'date': date});
  }

  @override
  Future<SmCourierPayoutReport> courierPayouts({required String from, required String to}) async {
    payoutCalls.add((from, to));
    return SmCourierPayoutReport.fromMap({'from': from, 'to': to, ...payoutResult});
  }

  @override
  Future<Map<String, dynamic>> markCourierPaid({
    required String courierId,
    required List<String> orderIds,
    required String clientRequestId,
    String note = '',
  }) async {
    marks.add((courierId, orderIds, clientRequestId, note));
    if (markError != null) throw markError!;
    return {'ok': true, 'count': orderIds.length, 'total': 11000};
  }

  final payoutCalls = <(String, String)>[];
  final marks = <(String, List<String>, String, String)>[];
  Map<String, dynamic> payoutResult = {};
  Object? markError;

  @override
  Future<SmStatsReport> stats({required String from, required String to, bool backfill = false}) async {
    statsCalls.add((from: from, to: to, backfill: backfill));
    return SmStatsReport.fromMap({'from': from, 'to': to, ...statsResult});
  }
}

Future<void> _big(WidgetTester t) async {
  await t.binding.setSurfaceSize(const Size(1400, 2400));
  addTearDown(() => t.binding.setSurfaceSize(null));
}

void main() {
  group('тоза ҳисоб', () {
    test('тавсия харид = ceil(shortfall + demand×%) — чегаралар', () {
      expect(smSuggestedPurchase(shortfall: 2.5, demand: 12.5, reservePercent: 10), 4); // 2.5+1.25=3.75 → 4
      expect(smSuggestedPurchase(shortfall: 0, demand: 4, reservePercent: 0), 0);
      expect(smSuggestedPurchase(shortfall: 0, demand: 4, reservePercent: 25), 1); // 1.0 → 1 (аниқ)
      expect(smSuggestedPurchase(shortfall: 3, demand: 0, reservePercent: 50), 3);
      expect(smSuggestedPurchase(shortfall: 0.001, demand: 0, reservePercent: 0), 1);
      expect(smSuggestedPurchase(shortfall: 0.1, demand: 0.2, reservePercent: 10), 1, reason: '0.1+0.02 float хатосиз');
      expect(smSuggestedPurchase(shortfall: -5, demand: 10, reservePercent: -10), 0, reason: 'манфий → 0');
    });

    test('CSV: BOM, сарлавҳа, қочириш, захира % ва тавсия; мижоз маълумоти йўқ', () {
      final r = SmProcurementReport.fromMap({
        ..._proc,
        'offers': [
          ...(_proc['offers'] as List),
          {'productId': 'x', 'name': 'Нон, "оқ"', 'groupId': 'bread', 'categoryId': 'unknown', 'unit': 'piece', 'demandQty': 2, 'shortfall': 2, 'orderCount': 1},
        ],
      });
      final csv = smProcurementCsv(r, 10);
      expect(csv.startsWith('﻿Бўлим,Гуруҳ,Нав,Таклиф,Бирлик,Талаб,Бўш қолдиқ,Жисмоний қолдиқ,Етишмайди,Захира %,Тавсия харид,Буюртмалар\r\n'), isTrue);
      expect(csv.codeUnitAt(0), 0xFEFF);
      expect(csv, contains('Сабзавотлар,Картошка,Маҳаллий,Картошка,кг,12.5,0,10,2.5,10,4,3'));
      expect(csv, contains('Сут маҳсулотлари,Сут,,Сут 1 л 1 л,л,4,16,20,0,10,1,2'));
      expect(csv, contains('Бўлимсиз,bread,,"Нон, ""оқ""",дона,2,,,2,10,3,1'));
    });

    test('аналитика: топ гуруҳлар кунлардан йиғилади (тугамаган кун кирмайди), манба йиғиндиси', () {
      final r = SmStatsReport.fromMap({
        'from': 'a', 'to': 'b',
        'days': [_day('2026-11-20'), _day('2026-11-21'), _day('2026-11-22', partial: true)],
      });
      final top = r.topGroups();
      expect(top.map((g) => [g.groupId, g.sum, g.lines]), [
        ['beef', 160000, 4],
        ['potato', 40000, 6],
      ]);
      expect(top.first.qty, {'kg': 3});
      expect(r.byOrigin, {'catalog': 4, 'quick': 0, 'weekly': 2, 'reorder': 2, 'unknown': 0});
    });

    test('Тошкент санаси: UTC 20:00 → эртанги кун', () {
      expect(smDateKey(smTashkentToday(DateTime.utc(2026, 11, 21, 20))), '2026-11-22');
      expect(smDateKey(smTashkentToday(DateTime.utc(2026, 11, 21, 18, 59))), '2026-11-21');
    });
  });

  group('origin (мижоз)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('бўш саватга биринчи манба; каталог саватига ҳафталик → weekly; бўшаса → catalog', () {
      final c = SupermarketController(api: FakeSupermarketApi());
      expect(c.cartOrigin, 'catalog');
      c.quickAdd(smOffersFixture().first, 1000);
      expect(c.cartOrigin, 'quick');
      c.addToCart('x', 1000); // каталогдан қўшимча — манба ўзгармайди
      expect(c.cartOrigin, 'quick');
      c.clearCart();
      expect(c.cartOrigin, 'catalog');
      c.addToCart('x', 1000);
      c.addLines([const SmCartLine('y', 1000)], origin: smOriginWeekly);
      expect(c.cartOrigin, 'weekly');
      c.addLines([const SmCartLine('z', 1000)], origin: smOriginReorder);
      expect(c.cartOrigin, 'weekly', reason: 'биринчи каталогдан ташқари манба сақланади');
      c.clearCart();
      c.addLines(const [], origin: smOriginReorder);
      expect(c.cartOrigin, 'catalog', reason: 'ҳеч нарса қўшилмади');
    });
  });

  group('«Харид режаси» таби', () {
    testWidgets('эслатма, сукут эртага, бўлим бўйича жадвал, захира % ўзгарса тавсия қайта ҳисобланади, CSV', (t) async {
      await _big(t);
      final s = _Fake();
      final saved = <(String, Uint8List)>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SmProcurementAdminTab(
            service: s,
            today: DateTime.utc(2026, 11, 21),
            saveFile: (n, b) async => saved.add((n, b)),
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('Тизим харид қилмайди, фақат ҳисоблайди. Таъминотчиларга ҳеч нарса юборилмайди.'), findsOneWidget);
      expect(s.procDates, ['2026-11-22']);
      expect(find.text('Сабзавотлар'), findsOneWidget);
      expect(find.text('Сут маҳсулотлари'), findsOneWidget);
      expect(find.text('2.5'), findsWidgets);
      Text sug(String id) => t.widget<Text>(find.byKey(ValueKey('sm_proc_suggest_$id')));
      expect(t.widget<Text>(find.byKey(const ValueKey('sm_proc_onhand_pot1'))).data, '10');
      expect(find.text('Бўш қолдиқ'), findsWidgets);
      expect(find.text('Жисмоний қолдиқ'), findsWidgets);
      expect(sug('pot1').data, '4');
      expect(sug('milk1').data, '1');
      await t.enterText(find.byKey(const ValueKey('sm_proc_reserve')), '0');
      await t.pump();
      expect(sug('pot1').data, '3');
      expect(sug('milk1').data, '0');
      expect(s.procDates.length, 1, reason: 'захира % — фақат клиентда, сервер чақирилмайди');
      await t.tap(find.byKey(const ValueKey('sm_proc_csv')));
      await t.pumpAndSettle();
      expect(saved.single.$1, 'ava_supermarket_harid_2026-11-22.csv');
      expect(utf8.decode(saved.single.$2), contains(',0,3,3')); // захира 0 → тавсия 3
      await t.tap(find.byKey(const ValueKey('sm_proc_today')));
      await t.pumpAndSettle();
      expect(s.procDates.last, '2026-11-21');
    });

    testWidgets('сервер хатоси — қизил матн, CSV ўчиқ', (t) async {
      await _big(t);
      final s = _Fake()..procError = const AdminSupermarketException('Бу амал учун рухсат йўқ. (PERMISSION_DENIED)');
      await t.pumpWidget(MaterialApp(home: Scaffold(body: SmProcurementAdminTab(service: s, today: DateTime.utc(2026, 11, 21)))));
      await t.pumpAndSettle();
      expect(find.textContaining('PERMISSION_DENIED'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('sm_proc_csv'))).onPressed, isNull);
    });
  });

  group('«Аналитика» таби', () {
    testWidgets('сукут: охирги 7 кун (кечагача); KPI; курьер тўлови маълум эмас; етишмаган кун → backfill', (t) async {
      await _big(t);
      final s = _Fake()
        ..statsResult = {
          'days': [_day('2026-11-19'), _day('2026-11-20')],
          'missing': ['2026-11-14'],
          'summary': {'orders': 8, 'delivered': 6, 'cancelled': 2, 'gmv': 240000, 'deliveryFeeRevenue': 24000, 'refundsTotal': 6000,
            'avgBasket': 40000, 'weeklyOrders': 2, 'courierPayout': null, 'netLogistics': null},
          'listsWithReminders': 5,
        };
      await t.pumpWidget(MaterialApp(home: Scaffold(body: SmAnalyticsAdminTab(service: s, today: DateTime.utc(2026, 11, 21)))));
      await t.pumpAndSettle();
      expect(s.statsCalls.single, (from: '2026-11-14', to: '2026-11-20', backfill: false));
      expect(find.descendant(of: find.byKey(const ValueKey('sm_kpi_orders')), matching: find.text('8')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('sm_kpi_net')), matching: find.text('маълум эмас')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('sm_kpi_reminders')), matching: find.text('5')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('sm_kpi_weekly')), matching: find.text('2')), findsOneWidget);
      expect(find.byKey(const ValueKey('sm_stats_day_2026-11-19')), findsOneWidget);
      expect(find.byKey(const ValueKey('sm_top_beef')), findsOneWidget);
      expect(find.text('Мол гўшти'), findsOneWidget, reason: 'гуруҳ номи таксономиядан');
      expect(find.textContaining('Ҳафталик сават: 2'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('sm_stats_backfill')));
      await t.pumpAndSettle();
      expect(s.statsCalls.last.backfill, isTrue);
    });

    testWidgets('соф логистика манфий — қизил (KPI ва кунлик жадвал)', (t) async {
      await _big(t);
      final s = _Fake()
        ..statsResult = {
          'days': [_day('2026-11-20', net: -3000)],
          'summary': {'orders': 4, 'deliveryFeeRevenue': 12000, 'courierPayout': 15000, 'netLogistics': -3000},
        };
      await t.pumpWidget(MaterialApp(home: Scaffold(body: SmAnalyticsAdminTab(service: s, today: DateTime.utc(2026, 11, 21)))));
      await t.pumpAndSettle();
      final kpi = find.descendant(of: find.byKey(const ValueKey('sm_kpi_net')), matching: find.byType(Text));
      final valueText = t.widgetList<Text>(kpi).firstWhere((w) => (w.data ?? '').contains('3'));
      expect(valueText.style?.color, Colors.red);
      expect(find.text('Етказиш зарар қилмоқда'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey('sm_stats_net_2026-11-20'))).style?.color, Colors.red);
    });
  });

  group('курьер тўлови', () {
    test('SmCourierPayout: fromMap/toMap, текширув; SmSettings доим courierPayout юборади (null — созланмаган)', () {
      expect(SmCourierPayout.fromMap({'mode': 'percent', 'percent': 13})!.toMap(), {'mode': 'percent', 'percent': 13});
      expect(SmCourierPayout.fromMap({'mode': 'fixed', 'fixedAmount': 6000})!.toMap(), {'mode': 'fixed', 'fixedAmount': 6000});
      expect(SmCourierPayout.fromMap({'mode': 'x'}), isNull);
      expect(SmCourierPayout.fromMap(null), isNull);
      expect(const SmCourierPayout.percent(101).problems(), isNotEmpty);
      expect(const SmCourierPayout.percent(100).problems(), isEmpty);
      expect(const SmCourierPayout.fixed(-1).problems(), isNotEmpty);
      expect(const SmCourierPayout.fixed(0).problems(), isEmpty);
      final s = SmSettings.fromMap({'stage': 'internal', 'courierPayout': {'mode': 'fixed', 'fixedAmount': 5000}});
      expect(s.toMap()['courierPayout'], {'mode': 'fixed', 'fixedAmount': 5000});
      expect(const SmSettings().toMap().containsKey('courierPayout'), isTrue);
      expect(const SmSettings().toMap()['courierPayout'], isNull);
      expect(const SmSettings(courierPayout: SmCourierPayout.percent(-5)).problems(), contains('Курьер улуши 0..100%'));
    });

    test('CSV: курьер, буюртма, ҳолат; карта/мижоз маълумоти йўқ', () {
      final r = SmCourierPayoutReport.fromMap(_payouts);
      final csv = smCourierPayoutCsv(r);
      expect(csv.codeUnitAt(0), 0xFEFF);
      expect(csv, contains('Курьер,Телефон,Буюртма,Сана,Етказиш ҳақи,Курьерга,Ҳолат\r\n'));
      expect(csv, contains('Бек,998931112233,o5,2026-11-20,1200,156,тўланган'));
      expect(csv, contains('Бек,998931112233,o6,2026-11-20,1200,6000,тўланмаган'));
      expect(csv, contains('Бек,998931112233,o2,2026-11-20,1100,,белгиланмаган'));
      expect(r.couriers.single.payable.map((o) => o.orderId), ['o6']);
    });

    testWidgets('таб: эслатма, курьер (исм+телефон), жами тўланмаган; «Тўланди» — фақат тўланмаган+суммали, изоҳ, калит; CSV', (t) async {
      await _big(t);
      final s = _Fake()..payoutResult = _payouts;
      final saved = <String>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SmCourierPayoutsAdminTab(
            service: s,
            today: DateTime.utc(2026, 11, 21),
            newRequestId: () => 'req-key-0001',
            saveFile: (n, b) async => saved.add(n),
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(s.payoutCalls.single, ('2026-11-15', '2026-11-21'));
      expect(find.textContaining('тизимдан ТАШҚАРИДА'), findsOneWidget);
      expect(find.text('Бек · 998931112233'), findsOneWidget);
      expect(find.textContaining('Жами тўланмаган: ${formatMoney(6000)}'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey('sm_cpay_state_o2'))).data, 'белгиланмаган');
      await t.tap(find.byKey(const ValueKey('sm_cpay_mark_998931112233')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('sm_cpay_note')), 'Humo 26.11');
      await t.tap(find.byKey(const ValueKey('sm_cpay_confirm')));
      await t.pumpAndSettle();
      final m = s.marks.single;
      expect([m.$1, m.$2, m.$3, m.$4], ['998931112233', ['o6'], 'req-key-0001', 'Humo 26.11']);
      expect(s.payoutCalls.length, 2, reason: 'belgilangandan keyin qayta yuklanadi');
      await t.tap(find.byKey(const ValueKey('sm_cpay_csv')));
      await t.pumpAndSettle();
      expect(saved.single, 'ava_supermarket_kuryer_2026-11-15_2026-11-21.csv');
    });

    testWidgets('таб: сервер рад этса (ALREADY_PAID) — қизил матн', (t) async {
      await _big(t);
      final s = _Fake()
        ..payoutResult = _payouts
        ..markError = const AdminSupermarketException('Бу буюртма аллақачон тўланган деб белгиланган. (ALREADY_PAID)');
      await t.pumpWidget(MaterialApp(home: Scaffold(body: SmCourierPayoutsAdminTab(service: s, today: DateTime.utc(2026, 11, 21)))));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('sm_cpay_mark_998931112233')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('sm_cpay_confirm')));
      await t.pumpAndSettle();
      expect(find.textContaining('ALREADY_PAID'), findsOneWidget);
    });

    testWidgets('аналитика: тўланган/тўланмаган плиткалари, қисман — «Қисман маълумот»', (t) async {
      await _big(t);
      final s = _Fake()
        ..statsResult = {
          'days': [{..._day('2026-11-20'), 'netLogistics': null, 'courierPayoutPartial': true}],
          'summary': {'orders': 4, 'courierPayout': 6156, 'courierPayoutPaid': 156, 'courierPayoutUnpaid': 6000, 'courierPayoutPartial': true, 'netLogistics': null},
        };
      await t.pumpWidget(MaterialApp(home: Scaffold(body: SmAnalyticsAdminTab(service: s, today: DateTime.utc(2026, 11, 21)))));
      await t.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const ValueKey('sm_kpi_payout_unpaid')), matching: find.text(formatMoney(6000))), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('sm_kpi_payout_paid')), matching: find.text(formatMoney(156))), findsOneWidget);
      expect(find.text('Қисман маълумот — ҳисобланмади'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey('sm_stats_net_2026-11-20'))).data, 'қисман');
    });
  });
  testWidgets('асосий экран: «Харид режаси» ва «Аналитика» таблари бор', (t) async {
    await _big(t);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SupermarketAdminScreen(service: _Fake()))));
    expect(find.text('Харид режаси'), findsOneWidget);
    expect(find.text('Аналитика'), findsOneWidget);
    expect(find.text('Курьерларга тўлов'), findsOneWidget);
  });
}
