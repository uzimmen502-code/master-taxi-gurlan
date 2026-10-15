// Marshrut yo'lovchi — begona haydovchi hujjatlari faqat SERVERDA
// (2026-10-08). `RidesRepository` endi ularni o'zi yozmaydi: CF chaqiradi.
// Firestore'ga tegadigan yagona yo'l — CF yetmaganda O'Z pending trip'ini
// bekor qilish; u bu yerda sinalmaydi (Firestore fake yo'q).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ava_gurlan/repositories/rides_repository.dart';

class _FakeDb extends Fake implements FirebaseFirestore {}

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
    final handler = fns.handlers[name];
    if (handler == null) {
      throw FirebaseFunctionsException(message: 'unavailable', code: 'unavailable');
    }
    return _FakeResult<T>(handler(parameters));
  }
}

class _FakeFunctions extends Fake implements FirebaseFunctions {
  final calls = <(String, Map<String, dynamic>)>[];
  final handlers = <String, Object? Function(Map)>{};

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _FakeCallable(name, this);
}

void main() {
  late _FakeFunctions fns;
  late RidesRepository repo;

  setUp(() {
    fns = _FakeFunctions();
    repo = RidesRepository(db: _FakeDb(), functions: fns);
  });

  test('markExpired — faqat CF (expired), klient haydovchi hujjatlariga yozmaydi', () async {
    fns.handlers['marshrutPassengerCloseOffer'] = (_) => {'ok': true, 'closed': true, 'status': 'expired'};
    await repo.markExpired('T1');
    expect(fns.calls, hasLength(1));
    expect(fns.calls.single.$1, 'marshrutPassengerCloseOffer');
    expect(fns.calls.single.$2, {'tripId': 'T1', 'outcome': 'expired'});
  });

  test('markExpired — CF xatosi OTILMAYDI (sweep yopadi), Firestore\'ga tegmaydi', () async {
    await repo.markExpired('T1'); // handler yo'q → unavailable; _FakeDb ishlatilsa — UnimplementedError
    expect(fns.calls.single.$2['outcome'], 'expired');
  });

  test('markCancelled — pending: faqat CF (cancelled)', () async {
    fns.handlers['marshrutPassengerCloseOffer'] = (_) => {'ok': true, 'closed': true, 'status': 'cancelled'};
    await repo.markCancelled('T1');
    expect(fns.calls.map((c) => c.$1), ['marshrutPassengerCloseOffer']);
    expect(fns.calls.single.$2, {'tripId': 'T1', 'outcome': 'cancelled'});
  });

  test('markCancelled — orada qabul qilingan: qabuldan keyingi bekor CF', () async {
    fns.handlers['marshrutPassengerCloseOffer'] = (_) => {'ok': true, 'closed': false, 'status': 'accepted'};
    fns.handlers['marshrutPassengerCancelAfterAccept'] = (_) => {'ok': true};
    await repo.markCancelled('T1');
    expect(fns.calls.map((c) => c.$1),
        ['marshrutPassengerCloseOffer', 'marshrutPassengerCancelAfterAccept']);
    expect(fns.calls.last.$2, {'tripId': 'T1', 'reason': 'passenger_cancel_after_accept'});
  });

  test('cancelMarshrutByPassenger — CF javobini qaytaradi (warning/remaining)', () async {
    fns.handlers['marshrutPassengerCancelAfterAccept'] = (_) => {'ok': true, 'warning': true, 'remaining': 1};
    final r = await repo.cancelMarshrutByPassenger(tripId: 'T1', reason: 'passenger_cancel_after_accept');
    expect(r['warning'], true);
    expect(r['remaining'], 1);
  });

  test('cancelMarshrutByPassenger — CF xatosi OTILADI (klient fallback yo\'q)', () async {
    await expectLater(
      repo.cancelMarshrutByPassenger(tripId: 'T1', reason: 'passenger_cancel_after_accept'),
      throwsA(isA<FirebaseFunctionsException>()),
    );
    expect(fns.calls.map((c) => c.$1), ['marshrutPassengerCancelAfterAccept']);
  });

  test('bo\'sh tripId — hech narsa chaqirilmaydi', () async {
    await repo.markExpired('');
    await repo.markCancelled('');
    expect(await repo.cancelMarshrutByPassenger(tripId: '', reason: 'x'), isEmpty);
    expect(fns.calls, isEmpty);
  });
}
