import 'package:ava_gurlan/repositories/taxi_billing_repository.dart';
import 'package:ava_gurlan/shared/widgets/intercity_billing_flow.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `publishTaxiTrip.requestId` idempotentligi: bir harakat = bir id.
/// Noaniq xatodan keyingi qayta urinish AYNI id, aniq javobdan keyin YANGI id.
class _FakeBilling implements TaxiBillingRepository {
  final requestIds = <String?>[];
  final payloads = <Map<String, Object?>>[];
  final outcomes = <Object>[]; // TaxiPublishResult yoki Exception
  var quoteCalls = 0;

  @override
  Future<TaxiFeeQuote> quote({required int farePerSeat}) async {
    quoteCalls++;
    return const TaxiFeeQuote(
      allowed: true,
      reason: 'ok',
      feeAmount: 0,
      quotedFee: 0,
      billable: false,
      sufficient: true,
      agreementRequired: false,
    );
  }

  @override
  Future<TaxiPublishResult> publish({
    required int farePerSeat,
    required String from,
    required String to,
    required String scheduleDate,
    required String startTime,
    required int seats,
    DateTime? departureAt,
    double? driverLat,
    double? driverLng,
    double? locationAccuracy,
    String? requestId,
  }) async {
    requestIds.add(requestId);
    payloads.add({'farePerSeat': farePerSeat, 'startTime': startTime});
    final o = outcomes.removeAt(0);
    if (o is Exception) throw o;
    return o as TaxiPublishResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TaxiPublishResult _ok(String id) => TaxiPublishResult(
    tripId: id, status: 'published', feeAmount: 0, walletBalance: null);

void main() {
  late _FakeBilling billing;
  late IntercityBillingFlow flow;
  var seq = 0;
  late DateTime now;

  setUp(() {
    billing = _FakeBilling();
    seq = 0;
    now = DateTime(2026, 10, 16, 15, 0);
    flow = IntercityBillingFlow(
      repository: billing,
      requestIdFactory: () => 'req_test_${++seq}',
      clock: () => now,
    );
  });

  Future<BuildContext> pumpContext(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })),
    ));
    return ctx;
  }

  Future<String?> publish(
    WidgetTester tester,
    BuildContext ctx, {
    int fare = 35000,
    DateTime? departure,
  }) async {
    // Geolocator platform kanali haqiqiy async talab qiladi -> runAsync.
    final r = await tester.runAsync(() => flow.publish(
          ctx,
          primaryColor: Colors.blue,
          farePerSeat: fare,
          from: 'Гурлан',
          to: 'Тошкент',
          scheduleDate: '2026-10-16',
          startTime: '16:00',
          seats: 4,
          departureAt: departure ?? DateTime(2026, 10, 16, 16, 0),
        ));
    await tester.pump();
    return r;
  }

  testWidgets('noaniq xato (unavailable) -> qayta urinish AYNI id, keyin muvaffaqiyat',
      (tester) async {
    final ctx = await pumpContext(tester);
    billing.outcomes
      ..add(const TaxiBillingException('unavailable', '', 'x'))
      ..add(_ok('T1'));

    expect(await publish(tester, ctx), isNull);
    expect(await publish(tester, ctx), 'T1');
    expect(billing.requestIds, ['req_test_1', 'req_test_1']);
  });

  testWidgets('muvaffaqiyatdan keyin yangi harakat -> YANGI id', (tester) async {
    final ctx = await pumpContext(tester);
    billing.outcomes..add(_ok('T1'))..add(_ok('T2'));
    await publish(tester, ctx);
    await publish(tester, ctx);
    expect(billing.requestIds, ['req_test_1', 'req_test_2']);
  });

  testWidgets('aniq rad etish (failed-precondition) -> keyingi bosish YANGI id',
      (tester) async {
    final ctx = await pumpContext(tester);
    billing.outcomes
      ..add(const TaxiBillingException(
          'failed-precondition', 'outstanding_debt', 'x'))
      ..add(_ok('T1'));
    expect(await publish(tester, ctx), isNull);
    expect(await publish(tester, ctx), 'T1');
    expect(billing.requestIds, ['req_test_1', 'req_test_2']);
  });

  testWidgets('noaniq xatodan keyin ma\'lumot o\'zgarsa (narx) -> YANGI id',
      (tester) async {
    final ctx = await pumpContext(tester);
    billing.outcomes
      ..add(const TaxiBillingException('deadline-exceeded', '', 'x'))
      ..add(_ok('T1'));
    await publish(tester, ctx, fare: 35000);
    await publish(tester, ctx, fare: 40000);
    expect(billing.requestIds, ['req_test_1', 'req_test_2']);
  });

  testWidgets('Firebase bo\'lmagan xato (tarmoq) noaniq hisoblanadi -> AYNI id',
      (tester) async {
    final ctx = await pumpContext(tester);
    billing.outcomes
      ..add(Exception('socket'))
      ..add(_ok('T1'));
    await publish(tester, ctx);
    await publish(tester, ctx);
    expect(billing.requestIds, ['req_test_1', 'req_test_1']);
  });

  testWidgets('o\'tib ketgan vaqt: serverga umuman murojaat yo\'q, sodda xabar',
      (tester) async {
    final ctx = await pumpContext(tester);
    final r = await publish(tester, ctx,
        departure: DateTime(2026, 10, 16, 8, 0));
    expect(r, isNull);
    expect(billing.quoteCalls, 0);
    expect(billing.requestIds, isEmpty);
    expect(find.text('taxi_reason_departure_in_past'), findsOneWidget);
  });

  testWidgets('server sababi (route_required) sodda xabar bilan, xom kodsiz',
      (tester) async {
    final ctx = await pumpContext(tester);
    billing.outcomes
        .add(const TaxiBillingException('failed-precondition', 'route_required', 'x'));
    await publish(tester, ctx);
    expect(find.text('taxi_reason_route_required'), findsOneWidget);
  });

  test('standart id serverga mos: 8..64 belgi, [A-Za-z0-9_-]', () {
    final re = RegExp(r'^[A-Za-z0-9_-]{8,64}$');
    final ids = {for (var i = 0; i < 50; i++) IntercityBillingFlow.generateRequestId()};
    expect(ids.length, 50);
    for (final id in ids) {
      expect(re.hasMatch(id), isTrue, reason: id);
    }
  });

  group('TaxiBillingRepository.publish payload', () {
    test('requestId yuboriladi; berilmasa maydon yo\'q (eski server mos)', () async {
      final fns = _FakeFunctions();
      final repo = TaxiBillingRepository(
          billingFunctions: fns, demandFunctions: fns);
      fns.result = {'tripId': 'T1', 'status': 'published', 'feeAmount': 0};
      await repo.publish(
        farePerSeat: 35000,
        from: 'a',
        to: 'b',
        scheduleDate: '2026-10-16',
        startTime: '16:00',
        seats: 4,
        requestId: 'pub_abcdefgh',
      );
      expect(fns.calls.single.$1, 'publishTaxiTrip');
      expect(fns.calls.single.$2['requestId'], 'pub_abcdefgh');
      await repo.publish(
        farePerSeat: 35000,
        from: 'a',
        to: 'b',
        scheduleDate: '2026-10-16',
        startTime: '16:00',
        seats: 4,
      );
      expect(fns.calls.last.$2.containsKey('requestId'), isFalse);
    });
  });
}

class _FakeResult<T> extends Fake implements HttpsCallableResult<T> {
  _FakeResult(this._data);
  final Object? _data;
  @override
  T get data => _data as T;
}

class _FakeCallable extends Fake implements HttpsCallable {
  _FakeCallable(this.name, this.fns);
  final String name;
  final _FakeFunctions fns;

  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    fns.calls.add((name, Map<String, dynamic>.from(parameters as Map)));
    return _FakeResult<T>(fns.result);
  }
}

class _FakeFunctions extends Fake implements FirebaseFunctions {
  final calls = <(String, Map<String, dynamic>)>[];
  Object? result = <String, dynamic>{};

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _FakeCallable(name, this);
}
