// Улгуржи «Етказилмади» харидор тасдиғи билан (эга, 2026-11-01): модел, харидор картаси
// («Тасдиқлайман» / «Олмоқчиман»), сотувчи қарори (муддат ўтгач), рўйхат белгиси, админ рўйхати,
// хато матнлари. Ҳаммаси серверда (`functions_demand/api/wholesale_failed.js`) — бу ерда фақат UI.
import 'package:ava_gurlan/features/wholesale/models/wholesale_order.dart';
import 'package:ava_gurlan/features/wholesale/repositories/wholesale_orders_repository.dart';
import 'package:ava_gurlan/features/wholesale/screens/wholesale_order_detail_screen.dart';
import 'package:ava_gurlan/features/wholesale/screens/wholesale_orders_screen.dart';
import 'package:ava_gurlan/features/wholesale/utils/wholesale_order_errors.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_delivery_failed_admin_list.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wholesale_orders_fakes.dart';

const _buyer = '998900000001';
const _seller = '998901111111';
const _stranger = '998907777777';
final _due = DateTime(2026, 11, 1, 12, 15);

Map<String, dynamic> _df({bool open = true, bool escalated = false, Map<String, dynamic>? resolution}) => {
      'seq': 1,
      'open': open,
      'stage': escalated ? 'awaiting_decision' : 'awaiting_buyer',
      'reasonCode': 'customer_absent',
      'escalateAt': Timestamp.fromDate(_due),
      'escalatedAt': escalated ? Timestamp.fromDate(_due) : null,
      'resolution': resolution,
    };

WholesaleOrder _order({String status = WholesaleOrderStatus.inDelivery, Map<String, dynamic>? df}) =>
    WholesaleOrder.fromMap('o1', {
      'buyerId': _buyer,
      'sellerId': _seller,
      'productTitle': 'Гуруч',
      'qty': 2,
      'unitPrice': 320000,
      'goodsTotal': 640000,
      'deliveryFee': 45000,
      'total': 685000,
      'status': status,
      'paymentMethod': WholesalePaymentMethod.cardOnDelivery,
      'cardPayment': {'status': 'awaiting'},
      'shipment': {'shipmentId': 's1', 'trackingNumber': 'AVA-1'},
      if (df != null) 'deliveryFailed': df,
    });

class _H {
  final demand = FakeFunctions('demand');
  late final repo = WholesaleOrdersRepository(firestore: FakeDb(), demandFunctions: demand, walletFunctions: FakeFunctions('wallet'));
}

Future<_H> _pump(WidgetTester tester, Widget Function(_H) child) async {
  final h = _H();
  tester.view.physicalSize = const Size(400 * 2, 1800 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child(h))));
  await tester.pumpAndSettle();
  return h;
}

Future<_H> _detail(WidgetTester tester, WholesaleOrder o, String viewer, {DateTime? now}) => _pump(
    tester,
    (h) => WholesaleOrderDetailView(order: o, viewerId: viewer, repository: h.repo, now: () => now ?? DateTime(2026, 11, 1, 12, 5)));

const _card = ValueKey('wholesale-delivery-failed-card');

void main() {
  group('модел', () {
    test('deliveryFailed: очиқ + in_delivery → pending; ёпиқ / бошқа ҳолат / майдон йўқ → йўқ', () {
      expect(_order(df: _df()).deliveryFailed.pending, isTrue);
      expect(_order(df: _df()).deliveryFailed.reasonCode, 'customer_absent');
      expect(_order(df: _df()).deliveryFailed.escalateAt, _due);
      expect(_order(df: _df(open: false, resolution: {'by': 'buyer', 'decision': 'continue'})).deliveryFailed.pending, isFalse);
      expect(_order(status: WholesaleOrderStatus.delivered, df: _df()).deliveryFailed.pending, isFalse);
      expect(_order().deliveryFailed.pending, isFalse, reason: 'эски ҳужжат');
    });

    test('canDecide: муддатдан 1 дақиқа олдин — йўқ; айнан муддатда — ҳа; эскалация — ҳа', () {
      final df = _order(df: _df()).deliveryFailed;
      expect(df.canDecide(_due.subtract(const Duration(minutes: 1))), isFalse);
      expect(df.canDecide(_due), isTrue);
      expect(_order(df: _df(escalated: true)).deliveryFailed.canDecide(DateTime(2020)), isTrue);
    });

    test('амаллар: харидор — жавоб; сотувчи — қарор; бегона — ҳеч нарса', () {
      final o = _order(df: _df());
      expect(WholesaleOrderActions.of(o, _buyer).answerDeliveryFailed, isTrue);
      expect(WholesaleOrderActions.of(o, _buyer).decideDeliveryFailed, isFalse);
      expect(WholesaleOrderActions.of(o, _seller).decideDeliveryFailed, isTrue);
      expect(WholesaleOrderActions.of(o, _seller).answerDeliveryFailed, isFalse);
      final s = WholesaleOrderActions.of(o, _stranger);
      expect([s.answerDeliveryFailed, s.decideDeliveryFailed], [false, false]);
    });

    test('курьер жавоби: awaitingBuyer / stage / resolution; эски сервер (refused) — кутиш йўқ', () {
      final r = WholesaleDeliveryFailedReport.fromMap({'status': 'in_delivery', 'awaitingBuyer': true, 'stage': 'awaiting_buyer', 'escalateAtMs': 1000});
      expect([r.pending, r.awaitingDecision, r.escalateAt?.millisecondsSinceEpoch], [true, false, 1000]);
      final s = WholesaleDeliveryFailedReport.fromMap({'pending': false, 'resolution': {'decision': 'continue'}});
      expect([s.pending, s.continued], [false, true]);
      expect(WholesaleDeliveryFailedReport.fromMap({'status': 'refused', 'idempotent': true}).pending, isFalse);
    });

    test('хато матнлари: df_not_pending/df_state_changed → ҳолат ўзгарди; decision_not_yet; not_decider → рухсат йўқ', () {
      String k(String r) => wholesaleOrderErrorKey(WholesaleOrderException('failed-precondition', r));
      expect(k('df_not_pending'), 'wholesale_df_err_state');
      expect(k('df_state_changed'), 'wholesale_df_err_state');
      expect(k('decision_not_yet'), 'wholesale_df_err_not_yet');
      expect(k('not_decider'), 'wholesale_order_err_not_party');
    });
  });

  group('харидор', () {
    testWidgets('карта кўринади; «Тасдиқлайман» → тасдиқ ойнаси → respond(confirm)', (tester) async {
      final h = await _detail(tester, _order(df: _df()), _buyer);
      h.demand.handlers['respondWholesaleDeliveryFailed'] = (_) => {'ok': true, 'status': 'refused'};
      expect(find.byKey(_card), findsOneWidget);
      expect(find.text('wholesale_df_buyer_title'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wholesale-df-confirm')));
      await tester.pumpAndSettle();
      expect(h.demand.calls, isEmpty, reason: 'аввал тасдиқ ойнаси');
      await tester.tap(find.byKey(const ValueKey('wholesale-confirm-yes')));
      await tester.pumpAndSettle();
      expect(h.demand.calls.single.$1, 'respondWholesaleDeliveryFailed');
      expect(h.demand.calls.single.$2, {'orderId': 'o1', 'decision': 'confirm'});
    });

    testWidgets('«Олмоқчиман» → respond(reject), ойнасиз', (tester) async {
      final h = await _detail(tester, _order(df: _df()), _buyer);
      h.demand.handlers['respondWholesaleDeliveryFailed'] = (_) => {'ok': true, 'status': 'in_delivery'};
      await tester.tap(find.byKey(const ValueKey('wholesale-df-want-it')));
      await tester.pumpAndSettle();
      expect(h.demand.calls.single.$2, {'orderId': 'o1', 'decision': 'reject'});
    });

    testWidgets('сервер «ҳолат ўзгарди» деса — тушунарли матн', (tester) async {
      final h = await _detail(tester, _order(df: _df()), _buyer);
      h.demand.handlers['respondWholesaleDeliveryFailed'] = (_) => throw fnError('failed-precondition', 'df_state_changed');
      await tester.tap(find.byKey(const ValueKey('wholesale-df-want-it')));
      await tester.pumpAndSettle();
      expect(find.text('wholesale_df_err_state'), findsOneWidget);
    });

    testWidgets('сўров ёпилган / йўқ — карта йўқ', (tester) async {
      await _detail(tester, _order(df: _df(open: false, resolution: {'by': 'buyer', 'decision': 'continue'})), _buyer);
      expect(find.byKey(_card), findsNothing);
    });
  });

  group('сотувчи', () {
    testWidgets('муддатдан олдин: карта бор, тугмалар ўчиқ', (tester) async {
      await _detail(tester, _order(df: _df()), _seller, now: _due.subtract(const Duration(seconds: 1)));
      expect(find.byKey(_card), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('wholesale-df-failed'))).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('wholesale-df-deliver'))).onPressed, isNull);
      expect(find.byKey(const ValueKey('wholesale-df-confirm')), findsNothing, reason: 'харидор тугмаси эмас');
    });

    testWidgets('муддатда: «Етказилмади» → ойна → resolve(failed); «Етказилсин» → resolve(deliver)', (tester) async {
      final h = await _detail(tester, _order(df: _df()), _seller, now: _due);
      h.demand.handlers['resolveWholesaleDeliveryFailed'] = (_) => {'ok': true};
      await tester.tap(find.byKey(const ValueKey('wholesale-df-failed')));
      await tester.pumpAndSettle();
      expect(find.text('wholesale_df_seller_failed_dialog'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wholesale-confirm-yes')));
      await tester.pumpAndSettle();
      expect(h.demand.calls.last.$2, {'orderId': 'o1', 'decision': 'failed'});
      await tester.tap(find.byKey(const ValueKey('wholesale-df-deliver')));
      await tester.pumpAndSettle();
      expect(h.demand.calls.last.$2, {'orderId': 'o1', 'decision': 'deliver'});
      expect(h.demand.calls.length, 2);
    });

    testWidgets('бегона — карта йўқ', (tester) async {
      await _detail(tester, _order(df: _df()), _stranger);
      expect(find.byKey(_card), findsNothing);
    });
  });

  testWidgets('рўйхат: очиқ сўровда белги, ёпиқда йўқ', (tester) async {
    await _pump(tester, (_) => Column(children: [
          WholesaleOrderTile(order: _order(df: _df()), onTap: () {}),
          WholesaleOrderTile(order: _order(df: _df(open: false)), onTap: () {}),
        ]));
    expect(find.byKey(const ValueKey('wholesale-df-badge')), findsOneWidget);
  });

  group('админ рўйхати', () {
    testWidgets('элементлар (телефон фақат охирги 4); муддат ўтмаган — тугма ўчиқ; ўтгани — қарор → resolve + қайта юклаш', (tester) async {
      final h = _H();
      var lists = 0;
      h.demand.handlers['listWholesaleDeliveryFailedPending'] = (_) {
        lists += 1;
        return {
          'ok': true,
          'items': [
            {'orderId': 'o1', 'productTitle': 'Гуруч', 'qty': 2, 'total': 685000, 'stage': 'awaiting_decision', 'reasonCode': 'customer_refused', 'canDecide': true, 'buyerTail': '0001', 'sellerTail': '1111', 'courierTail': '2222'},
            {'orderId': 'o2', 'productTitle': 'Ун', 'stage': 'awaiting_buyer', 'reasonCode': 'other', 'canDecide': false, 'escalateAtMs': DateTime(2099).millisecondsSinceEpoch},
          ],
        };
      };
      h.demand.handlers['resolveWholesaleDeliveryFailed'] = (_) => {'ok': true};
      tester.view.physicalSize = const Size(400 * 2, 1800 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(children: [WholesaleDeliveryFailedAdminList(repository: h.repo)]))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wdf-item-o1')), findsOneWidget);
      expect(find.byKey(const ValueKey('wdf-item-o2')), findsOneWidget);
      expect(find.textContaining('***0001'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('wdf-failed-o2'))).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('wdf-deliver-o1')));
      await tester.pumpAndSettle();
      expect(h.demand.calls.where((c) => c.$1 == 'resolveWholesaleDeliveryFailed').single.$2, {'orderId': 'o1', 'decision': 'deliver'});
      expect(lists, 2, reason: 'қарордан кейин рўйхат янгиланади');
    });

    testWidgets('рухсат йўқ (permission-denied) — хато матни, рўйхат йўқ', (tester) async {
      final h = _H();
      h.demand.handlers['listWholesaleDeliveryFailedPending'] = (_) => throw fnError('permission-denied', 'permission-denied');
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(children: [WholesaleDeliveryFailedAdminList(repository: h.repo)]))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wdf-item-o1')), findsNothing);
      expect(find.text('delivery_failed_decide_empty'), findsNothing);
    });
  });
}
