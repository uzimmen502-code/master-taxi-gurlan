// 3b: курьер LEG амаллари — улгуржи жўнатмасида «Етказилмади» (эга, 2026-11-01: харидор
// тасдиғи билан; охирги LEG, посилка қўлда), қайтиш LEG'ида топшириш коди; оддий жўнатмада йўқ.
import 'package:ava_gurlan/features/demand_offer/domain/demand_match.dart';
import 'package:ava_gurlan/features/logistics/data/logistics_repository.dart';
import 'package:ava_gurlan/features/logistics/domain/logistics_models.dart';
import 'package:ava_gurlan/features/logistics/services/logistics_photo_storage.dart';
import 'package:ava_gurlan/features/logistics/ui/leg_actions.dart';
import 'package:ava_gurlan/features/wholesale/repositories/wholesale_orders_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wholesale_orders_fakes.dart';

class _FakeLogistics extends Fake implements LogisticsRepository {
  _FakeLogistics(this.shipment);
  final Map<String, dynamic> shipment;

  @override
  Stream<Shipment?> watchShipment(String shipmentId) => Stream.value(Shipment.fromMap(shipmentId, shipment));
}

class _FakePhotos extends Fake implements LogisticsPhotoStorage {}

DemandMatch _match(String status, {int legIndex = 0, int legCount = 1, String shipmentId = 's1'}) => DemandMatch.fromMap('l1_998903333333', {
      'demandId': 'l1',
      'providerId': '998903333333',
      'module': 'logistics',
      'mode': 'quote',
      'status': status,
      'projection': {
        'attributes': {'shipmentId': shipmentId, 'trackingNumber': 'AVA-1', 'legIndex': legIndex, 'legCount': legCount},
      },
    });

const _noRequest = {'ok': true, 'orderId': 'o1', 'status': 'in_delivery', 'pending': false, 'stage': null, 'resolution': null};

Future<FakeFunctions> _pump(WidgetTester tester, DemandMatch m, Map<String, dynamic> shipment,
    {Map<String, dynamic>? state = _noRequest}) async {
  final demand = FakeFunctions('demand');
  if (state != null) demand.handlers['getWholesaleDeliveryFailedState'] = (_) => state;
  tester.view.physicalSize = const Size(400 * 2, 1600 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: LogisticsLegActions(
        match: m,
        providerId: '998903333333',
        repository: _FakeLogistics(shipment),
        photos: _FakePhotos(),
        wholesaleRepository: WholesaleOrdersRepository(
          firestore: FakeDb(),
          demandFunctions: demand,
          walletFunctions: FakeFunctions('wallet'),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return demand;
}

const _refused = ValueKey('wholesale-courier-refused');
const _yes = ValueKey('wholesale-courier-refused-yes');
const _wait = ValueKey('wholesale-courier-failed-wait');
const _returnCode = ValueKey('wholesale-courier-return-code');
const _wholesale = {'source': 'wholesale', 'wholesaleOrderId': 'o1'};

List<(String, Map<String, dynamic>)> _calls(FakeFunctions f, String name) => f.calls.where((c) => c.$1 == name).toList();

void main() {
  testWidgets('«Етказилмади» → сабаб (мажбурий) + изоҳ → callable (reasonCode) → кутиш блоки', (tester) async {
    final demand = await _pump(tester, _match('in_progress'), _wholesale);
    final escalate = DateTime.now().add(const Duration(minutes: 15)).millisecondsSinceEpoch;
    demand.handlers['markWholesaleBuyerRefused'] =
        (_) => {'ok': true, 'status': 'in_delivery', 'awaitingBuyer': true, 'stage': 'awaiting_buyer', 'escalateAtMs': escalate};
    expect(_calls(demand, 'getWholesaleDeliveryFailedState').single.$2, {'orderId': 'o1'});
    expect(find.byKey(_refused), findsOneWidget);
    expect(find.text('wholesale_courier_failed_btn'), findsOneWidget);
    await tester.tap(find.byKey(_refused));
    await tester.pumpAndSettle();
    // Сабабсиз тасдиқлаб бўлмайди.
    expect(tester.widget<FilledButton>(find.byKey(_yes)).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('wholesale-failed-reason-customer_absent')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'эшикни очмади');
    await tester.tap(find.byKey(_yes));
    await tester.pumpAndSettle();
    expect(_calls(demand, 'markWholesaleBuyerRefused').single.$2,
        {'orderId': 'o1', 'reasonCode': 'customer_absent', 'reason': 'эшикни очмади'});
    expect(find.byKey(_wait), findsOneWidget);
    expect(find.byKey(_refused), findsNothing);
    expect(find.text('wholesale_courier_failed_sent'), findsWidgets, reason: 'snack');
  });

  testWidgets('сервер рад этса (parcel_not_in_hand) — тушунарли матн, кутиш блоки йўқ', (tester) async {
    final demand = await _pump(tester, _match('in_progress'), _wholesale);
    demand.handlers['markWholesaleBuyerRefused'] = (_) => throw fnError('failed-precondition', 'parcel_not_in_hand');
    await tester.tap(find.byKey(_refused));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wholesale-failed-reason-other')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_yes));
    await tester.pumpAndSettle();
    expect(find.text('wholesale_order_err_parcel_not_in_hand'), findsOneWidget);
    expect(find.byKey(_wait), findsNothing);
  });

  testWidgets('экран очилганда сўров очиқ — кутиш блоки (тугма йўқ); муддат ўтган — «сотувчи қарорини кутяпмиз»', (tester) async {
    await _pump(tester, _match('in_progress'), _wholesale, state: {
      'ok': true, 'status': 'in_delivery', 'pending': true, 'stage': 'awaiting_decision', 'escalated': true,
      'escalateAtMs': DateTime(2026, 1, 1).millisecondsSinceEpoch,
    });
    expect(find.byKey(_wait), findsOneWidget);
    expect(find.byKey(_refused), findsNothing);
    expect(find.text('wholesale_courier_failed_wait_seller'), findsOneWidget);
  });

  testWidgets('«давом этсин» қарори — изоҳ ва тугма яна кўринади; эски сервер (ҳолат callable йўқ) — тугма аввалгидек', (tester) async {
    await _pump(tester, _match('in_progress'), _wholesale, state: {
      'ok': true, 'status': 'in_delivery', 'pending': false, 'resolution': {'by': 'buyer', 'decision': 'continue'},
    });
    expect(find.text('wholesale_courier_failed_continue'), findsOneWidget);
    expect(find.byKey(_refused), findsOneWidget);
  });

  testWidgets('ҳолат callable йўқ (эски сервер) — хато кўрсатилмайди, тугма бор', (tester) async {
    await _pump(tester, _match('in_progress'), _wholesale, state: null);
    expect(find.byKey(_refused), findsOneWidget);
    expect(find.byKey(_wait), findsNothing);
  });

  testWidgets('ўрта LEG ёки оддий жўнатма — «Етказилмади» йўқ', (tester) async {
    await _pump(tester, _match('in_progress', legIndex: 0, legCount: 2), _wholesale);
    expect(find.byKey(_refused), findsNothing);
  });

  testWidgets('оддий (улгуржи бўлмаган) жўнатма — улгуржи амаллари йўқ, ҳолат сўралмайди', (tester) async {
    final demand = await _pump(tester, _match('in_progress', shipmentId: 's2'), {});
    expect(find.byKey(_refused), findsNothing);
    expect(find.byKey(_returnCode), findsNothing);
    expect(demand.calls, isEmpty);
  });

  testWidgets('қайтиш LEG\'и (accepted): топшириш коди кўрсатилади', (tester) async {
    final demand =
        await _pump(tester, _match('accepted'), {'source': 'wholesale_return', 'wholesaleOrderId': 'o1'});
    demand.handlers['getWholesaleReturnHandoverCode'] =
        (_) => {'orderId': 'o1', 'shipmentId': 's1', 'trackingNumber': 'AVA-R1', 'handoverCode': '731905'};
    expect(find.byKey(_refused), findsNothing);
    await tester.tap(find.byKey(_returnCode));
    await tester.pumpAndSettle();
    expect(demand.calls.single.$2, {'orderId': 'o1'});
    expect(find.text('731905'), findsOneWidget);
  });
}
