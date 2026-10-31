// 3b: курьер LEG амаллари — улгуржи жўнатмасида «Харидор тўламади» (охирги
// LEG, посилка қўлда), қайтиш LEG'ида топшириш коди; оддий жўнатмада йўқ.
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

Future<FakeFunctions> _pump(WidgetTester tester, DemandMatch m, Map<String, dynamic> shipment) async {
  final demand = FakeFunctions('demand');
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
const _returnCode = ValueKey('wholesale-courier-return-code');

void main() {
  testWidgets('улгуржи охирги LEG, посилка қўлда: «Харидор тўламади» → тасдиқ → callable', (tester) async {
    final demand = await _pump(tester, _match('in_progress'), {'source': 'wholesale', 'wholesaleOrderId': 'o1'});
    demand.handlers['markWholesaleBuyerRefused'] = (_) => {'ok': true, 'status': 'refused'};
    expect(find.byKey(_refused), findsOneWidget);
    await tester.tap(find.byKey(_refused));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'эшикни очмади');
    await tester.tap(find.byKey(const ValueKey('wholesale-courier-refused-yes')));
    await tester.pumpAndSettle();
    expect(demand.calls.single.$1, 'markWholesaleBuyerRefused');
    expect(demand.calls.single.$2, {'orderId': 'o1', 'reason': 'эшикни очмади'});
  });

  testWidgets('сервер рад этса (parcel_not_in_hand) — тушунарли матн', (tester) async {
    final demand = await _pump(tester, _match('in_progress'), {'source': 'wholesale', 'wholesaleOrderId': 'o1'});
    demand.handlers['markWholesaleBuyerRefused'] = (_) => throw fnError('failed-precondition', 'parcel_not_in_hand');
    await tester.tap(find.byKey(_refused));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wholesale-courier-refused-yes')));
    await tester.pumpAndSettle();
    expect(find.text('wholesale_order_err_parcel_not_in_hand'), findsOneWidget);
  });

  testWidgets('ўрта LEG ёки оддий жўнатма — «Харидор тўламади» йўқ', (tester) async {
    await _pump(tester, _match('in_progress', legIndex: 0, legCount: 2), {'source': 'wholesale', 'wholesaleOrderId': 'o1'});
    expect(find.byKey(_refused), findsNothing);
  });

  testWidgets('оддий (улгуржи бўлмаган) жўнатма — улгуржи амаллари йўқ', (tester) async {
    await _pump(tester, _match('in_progress', shipmentId: 's2'), {});
    expect(find.byKey(_refused), findsNothing);
    expect(find.byKey(_returnCode), findsNothing);
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
