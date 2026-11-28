// «AVA Супермаркет» ҳамкорга тўлов (эга 2026-11-28): админ таби, ҳамкор картаси, соф ёрдамчилар.
import 'package:ava_gurlan/features/admin_web/screens/supermarket_partner_payouts_admin_tab.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_sm_partner_payout_service.dart';
import 'package:ava_gurlan/features/supermarket/partner/sm_partner_payouts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../restaurants/restaurants_l10n_harness.dart';

const _k1 = 'aaaaaaaaaaaaaaaa';

Map<String, dynamic> _listMap({bool detail = false, int? bp = 1000}) => {
      'settings': {'stage': 'internal', 'commissionBp': bp, 'version': 2},
      'partners': [
        {'partnerKey': _k1, 'companyName': 'Деҳқон ММ', 'balance': 42660, 'accruedTotal': 42660, 'openCount': 2, 'blockedCount': 1},
      ],
      'blocked': [
        {'payableId': 'o3__$_k1', 'orderId': 'o3', 'partnerKey': _k1, 'status': 'blocked', 'blockReason': 'WEIGH_PENDING', 'goodsBasis': 80000},
      ],
      if (detail) ...{
        'payables': [
          {'payableId': 'o1__$_k1', 'orderId': 'o1', 'partnerKey': _k1, 'status': 'accrued', 'goodsBasis': 35400, 'commissionBp': 1000, 'commission': 3540, 'amount': 31860},
          {'payableId': 'o2__$_k1', 'orderId': 'o2', 'partnerKey': _k1, 'status': 'accrued', 'goodsBasis': 12000, 'commissionBp': 1000, 'commission': 1200, 'amount': 10800},
          {'payableId': 'o3__$_k1', 'orderId': 'o3', 'partnerKey': _k1, 'status': 'blocked', 'blockReason': 'WEIGH_PENDING', 'goodsBasis': 80000},
        ],
        'payments': [],
      },
    };

class _FakeSvc extends AdminSmPartnerPayoutService {
  final marks = <Map<String, dynamic>>[];
  final reversals = <(String, String)>[];
  final saves = <Map<String, dynamic>>[];

  @override
  Future<SmPpList> list({String? partnerKey}) async => SmPpList.fromMap(_listMap(detail: partnerKey != null));

  @override
  Future<Map<String, dynamic>> markPaid({
    required String partnerKey,
    required List<String> payableIds,
    required String method,
    required String clientRequestId,
    String reference = '',
  }) async {
    marks.add({'partnerKey': partnerKey, 'payableIds': payableIds, 'method': method, 'rid': clientRequestId, 'reference': reference});
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> reverse(String payableId, String reason) async {
    reversals.add((payableId, reason));
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> saveSettings({required String stage, int? commissionBp, bool setBp = true, required String reason}) async {
    saves.add({'stage': stage, 'commissionBp': commissionBp, 'reason': reason});
    return {'ok': true};
  }
}

void main() {
  test('комиссия % ↔ базис пункт: бутун, 2 каср, 0..100; нотўғри → null', () {
    expect(smPercentTextToBp('12.5'), 1250);
    expect(smPercentTextToBp('12,5'), 1250);
    expect(smPercentTextToBp('10'), 1000);
    expect(smPercentTextToBp('0'), 0);
    expect(smPercentTextToBp('0.05'), 5);
    expect(smPercentTextToBp('100'), 10000);
    for (final bad in ['100.01', '12.555', '-1', 'abc', '', '1e2', '101']) {
      expect(smPercentTextToBp(bad), isNull, reason: bad);
    }
    expect([smBpToPercent(1250), smBpToPercent(1000), smBpToPercent(5), smBpToPercent(10), smBpToPercent(0)], ['12.5', '10', '0.05', '0.1', '0']);
  });

  test('модел: рўйхат, блок сабаби матни, тўланадиган/қайтариладиган белгилари', () {
    final l = SmPpList.fromMap(_listMap(detail: true));
    expect([l.settings.commissionBp, l.partners.single.balance, l.payables.length, l.blocked.single.blockReason], [1000, 42660, 3, 'WEIGH_PENDING']);
    expect([l.payables[0].payable, l.payables[0].reversible, l.payables[2].payable, l.payables[2].reversible], [true, true, false, false]);
    expect(smPpBlockReasonText('RULE_NOT_SET'), 'Комиссия қоидаси белгиланмаган');
    expect(SmPpList.fromMap(const {}).partners, isEmpty);
  });

  testWidgets('админ таби: ҳамкорни танлаш → 2 ёзувни белгилаш → «Тўланди» (нақд) — битта clientRequestId; қайтариш сабаб билан', (t) async {
    await t.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final s = _FakeSvc();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SmPartnerPayoutsAdminTab(service: s, today: () => '2026-11-28', newRequestId: () => 'rid-00000001'))));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('smpp_partner_$_k1')), findsOneWidget);
    expect(find.byKey(const ValueKey('smpp_blocked_o3__$_k1')), findsOneWidget);
    expect(find.text('Тортилмаган маҳсулот бор (етказилган)'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('smpp_partner_$_k1')));
    await t.pumpAndSettle();
    // blocked ёзувни белгилаб бўлмайди
    final blockedTile = t.widget<CheckboxListTile>(find.byKey(const ValueKey('smpp_row_o3__$_k1')));
    expect(blockedTile.onChanged, isNull);
    await t.tap(find.byKey(const ValueKey('smpp_row_o1__$_k1')));
    await t.tap(find.byKey(const ValueKey('smpp_row_o2__$_k1')));
    await t.pumpAndSettle();
    expect(find.textContaining('42 660'), findsWidgets);
    await t.tap(find.byKey(const ValueKey('smpp_mark_paid')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('smpp_paid_ok')));
    await t.pumpAndSettle();
    expect(s.marks.single['payableIds'], ['o1__$_k1', 'o2__$_k1']);
    expect([s.marks.single['method'], s.marks.single['rid'], s.marks.single['partnerKey']], ['cash', 'rid-00000001', _k1]);
    // қайтариш
    await t.tap(find.byKey(const ValueKey('smpp_reverse_o1__$_k1')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('smpp_ask_field')), 'Мижоз қайтарди');
    await t.tap(find.byKey(const ValueKey('smpp_ask_ok')));
    await t.pumpAndSettle();
    expect(s.reversals.single, ('o1__$_k1', 'Мижоз қайтарди'));
  });

  testWidgets('админ таби: банк ўтказмаси рақамсиз юборилмайди; созлама — нотўғри % рад, тўғри — bp билан', (t) async {
    await t.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final s = _FakeSvc();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SmPartnerPayoutsAdminTab(service: s, today: () => '2026-11-28', newRequestId: () => 'rid-00000002'))));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('smpp_partner_$_k1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('smpp_row_o1__$_k1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('smpp_mark_paid')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('smpp_method')));
    await t.pumpAndSettle();
    await t.tap(find.text('Банк ўтказмаси').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('smpp_paid_ok')));
    await t.pumpAndSettle();
    expect(s.marks, isEmpty);
    expect(find.text('Банк ўтказмаси рақамини ёзинг'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('smpp_bp')), '12.555');
    await t.enterText(find.byKey(const ValueKey('smpp_reason')), 'Эга қарори');
    await t.tap(find.byKey(const ValueKey('smpp_save')));
    await t.pumpAndSettle();
    expect(s.saves, isEmpty);
    await t.enterText(find.byKey(const ValueKey('smpp_bp')), '12.5');
    await t.tap(find.byKey(const ValueKey('smpp_save')));
    await t.pumpAndSettle();
    expect(s.saves.single, {'stage': 'internal', 'commissionBp': 1250, 'reason': 'Эга қарори'});
  });

  testWidgets('ҳамкор картаси: ўчиқ — кўринмайди; ёқиқ — баланс, комиссия; манфий баланс — «қайтариш» матни; хато — кўринмайди', (t) async {
    final d = JsonL10nDelegate();
    Future<void> pump(Future<SmPartnerPayouts> Function() load) async {
      await t.pumpWidget(l10nApp(delegate: d, home: Scaffold(body: SingleChildScrollView(child: SmPartnerPayoutsCard(key: UniqueKey(), load: load)))));
      await t.pumpAndSettle();
    }

    await pump(() async => SmPartnerPayouts.fromMap(const {'ok': true, 'enabled': false}));
    expect(find.byKey(const ValueKey('smp_pay_card')), findsNothing);
    await pump(() async => throw Exception('net'));
    expect(find.byKey(const ValueKey('smp_pay_card')), findsNothing);
    await pump(() async => SmPartnerPayouts.fromMap(const {
          'enabled': true, 'balance': 31860, 'accruedTotal': 31860, 'paidTotal': 0, 'commissionBp': 1000,
          'payables': [{'orderId': 'abcdefgh', 'slotDate': '2026-11-28', 'status': 'accrued', 'goodsBasis': 35400, 'commission': 3540, 'amount': 31860}],
        }));
    expect(find.byKey(const ValueKey('smp_pay_card')), findsOneWidget);
    expect(find.text(d.tr('smp_pay_balance')), findsOneWidget);
    expect(find.text(d.tr('smp_pay_commission').replaceAll('{pct}', '10')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('smp_pay_toggle')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('smp_pay_row_abcdefgh')), findsOneWidget);
    expect(find.textContaining(d.tr('smp_pay_status_accrued')), findsOneWidget);
    await pump(() async => SmPartnerPayouts.fromMap(const {'enabled': true, 'balance': -21060, 'payables': []}));
    expect(find.text(d.tr('smp_pay_balance_negative')), findsOneWidget);
    expect(find.byKey(const ValueKey('smp_pay_empty')), findsOneWidget);
  });
}
