import 'package:ava_gurlan/features/courier/screens/courier_mfy_selection_screen.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:ava_gurlan/services/courier_route_service.dart';
import 'package:ava_gurlan/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../restaurants/restaurants_l10n_harness.dart';

/// МФЙ экрани `ready` буюртмаларни `courierListReadyOrders` callable'дан
/// олади: `orders` қоидаси capability курьерга тўғридан-тўғри рўйхат
/// бермайди (functions/test/orders_courier_rules.test.js).
class _FakeRouteService implements CourierRouteService {
  _FakeRouteService(this.responses);

  /// Ҳар чақириқда навбатдаги жавоб (рўйхат ёки хато).
  final List<Object> responses;
  int listCalls = 0;
  final coords = <(double?, double?)>[];

  @override
  Future<List<OrderModel>> listReadyOrders({double? lat, double? lng}) async {
    coords.add((lat, lng));
    final r = responses[listCalls < responses.length
        ? listCalls
        : responses.length - 1];
    listCalls += 1;
    if (r is List<OrderModel>) return r;
    throw r;
  }

  @override
  Future<({String? routeId, int count, String? error})> createRoute({
    required String courierPhone,
    required List<String> orderedOrderIds,
  }) async =>
      (routeId: null, count: 0, error: 'not used');

  @override
  Future<({String? routeId, int count, bool revived})> recoverOrphanRoute({
    required String courierPhone,
  }) async =>
      (routeId: null, count: 0, revived: false);
}

/// Ҳақиқий uz_Cyrl матнлар (калит унутилса — хом калит чиқади ва тест йиқилади).
final _l10n = JsonL10nDelegate('uz_Cyrl');

OrderModel _stop(String id, String? mfy) =>
    CourierRouteService.readyStopFromMap({
      'id': id,
      'mfy': mfy,
      'lat': 41.84,
      'lng': 60.39,
      'createdAtMs': 1000,
    });

Future<void> _pump(
  WidgetTester tester,
  _FakeRouteService service, {
  LocationCoords? gps,
}) async {
  await tester.pumpWidget(l10nApp(
    delegate: _l10n,
    home: CourierMfySelectionScreen(
      routeService: service,
      locate: () async => gps,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('readyStopFromMap: faqat marshrut maydonlari, PII bo\'sh', () {
    final o = CourierRouteService.readyStopFromMap({
      'id': 'o1',
      'mfy': 'Navoiy',
      'lat': 41.84,
      'lng': 60,
      'createdAtMs': 1700000000000,
    });
    expect(o.id, 'o1');
    expect(o.mfy, 'Navoiy');
    expect(o.lat, 41.84);
    expect(o.lng, 60.0);
    expect(o.createdAt, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    expect(o.status, 'ready');
    expect(o.userPhone, isEmpty);
    expect(o.userName, isEmpty);
    expect(o.address, isEmpty);
    expect(o.items, isEmpty);

    final bare = CourierRouteService.readyStopFromMap({'id': 'o2'});
    expect(bare.mfy, isNull);
    expect(bare.hasCoordinates, isFalse);
    expect(bare.createdAt, isNull);
  });

  testWidgets('callable ro\'yxati MFY bo\'yicha guruhlanadi', (tester) async {
    final service = _FakeRouteService([
      [_stop('a', 'Navoiy'), _stop('b', 'Navoiy'), _stop('c', null)],
    ]);
    await _pump(tester, service);

    expect(service.listCalls, 1);
    expect(find.text('Navoiy — 2 та'), findsOneWidget);
    expect(find.text('МФЙ аниқланмаган — 1 та'), findsOneWidget);

    await tester.tap(find.text('Navoiy — 2 та'));
    await tester.pump();
    expect(find.text('Маршрут яратиш (2 та буюртма)'), findsOneWidget);
  });

  testWidgets('bo\'sh ro\'yxat — pull-to-refresh qayta oladi', (tester) async {
    final service = _FakeRouteService([
      <OrderModel>[],
      [_stop('a', 'Yangiobod')],
    ]);
    await _pump(tester, service);
    expect(find.text('Фаол буюртма йўқ'), findsOneWidget);

    await tester.fling(
        find.text('Фаол буюртма йўқ'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(service.listCalls, 2);
    expect(find.text('Yangiobod — 1 та'), findsOneWidget);
  });

  testWidgets('xato ko\'rsatiladi va qayta urinish mumkin', (tester) async {
    final service = _FakeRouteService([
      Exception('permission-denied'),
      [_stop('a', 'Navoiy')],
    ]);
    await _pump(tester, service);
    expect(find.text(_l10n.tr('err_load_failed')), findsOneWidget);

    await tester.fling(
        find.text(_l10n.tr('err_load_failed')), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(service.listCalls, 2);
    expect(find.text('Navoiy — 1 та'), findsOneWidget);
  });

  // Geo 4-bosqich (D-GEO-3): GPS bo'lsa serverga uzatiladi (radius filtri).
  testWidgets('GPS bor — koordinata callable\'ga uzatiladi', (tester) async {
    final withGps = _FakeRouteService([<OrderModel>[]]);
    await _pump(tester, withGps,
        gps: const LocationCoords(lat: 41.84, lng: 60.39));
    expect(withGps.coords.single, (41.84, 60.39));
  });

  testWidgets('GPS yo\'q — koordinatasiz (server avvalgidek hammasini beradi)', (tester) async {
    final noGps = _FakeRouteService([<OrderModel>[]]);
    await _pump(tester, noGps);
    expect(noGps.coords.single, (null, null));
  });
}
