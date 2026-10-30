// C-2 (икки марта юбориш / идемпотентлик): яратиш callable'ларига ихтиёрий
// `requestId` узатилади; бўш бўлса юборилмайди (эски сервер учун ўзгариш йўқ).
import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/repositories/courier_capability_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

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
    return _FakeResult<T>(fns.reply);
  }
}

class _FakeFunctions extends Fake implements FirebaseFunctions {
  final calls = <(String, Map<String, dynamic>)>[];
  Object? reply = const {'ok': true};

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _FakeCallable(name, this);
}

void main() {
  late _FakeFunctions fns;
  setUp(() => fns = _FakeFunctions());

  group('restaurantRegister', () {
    test('requestId берилса — тўловга қўшилади, бошқа майдонлар ўзгармайди', () async {
      fns.reply = const {'restaurantId': 'r1', 'status': 'applied'};
      final repo = RestaurantsRepository(firestore: _FakeDb(), functions: fns);
      final res = await repo.register({'name': 'Oshxona'}, requestId: 'abcdef0123456789');
      expect(res['restaurantId'], 'r1');
      expect(fns.calls.single.$1, 'restaurantRegister');
      expect(fns.calls.single.$2, {'name': 'Oshxona', 'requestId': 'abcdef0123456789'});
    });

    test('requestId бўш — майдон юборилмайди', () async {
      final repo = RestaurantsRepository(firestore: _FakeDb(), functions: fns);
      await repo.register({'name': 'Oshxona'});
      expect(fns.calls.single.$2.containsKey('requestId'), isFalse);
    });
  });

  group('requestCapability (курьер)', () {
    test('requestId берилса — service билан бирга юборилади', () async {
      fns.reply = const {'status': 'applied'};
      final repo = CourierCapabilityRepository(db: _FakeDb(), functions: fns);
      final status = await repo.apply(requestId: 'abcdef0123456789');
      expect(status, 'applied');
      expect(fns.calls.single.$1, 'requestCapability');
      expect(fns.calls.single.$2, {'service': 'courier', 'requestId': 'abcdef0123456789'});
    });

    test('requestId бўш — эски тўлов ({service})', () async {
      final repo = CourierCapabilityRepository(db: _FakeDb(), functions: fns);
      await repo.apply();
      expect(fns.calls.single.$2, {'service': 'courier'});
    });
  });
}
