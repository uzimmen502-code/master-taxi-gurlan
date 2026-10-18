import 'package:ava_gurlan/core/utils/idempotency_keys.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  int n = 0;
  IdempotencyKeys make() => IdempotencyKeys(generator: () => 'key-${++n}');

  setUp(() => n = 0);

  test('REGRESSION: бир ният — бир калит (қайта уриниш пулни яна емайди)', () {
    final k = make();
    final first = k.keyFor('pkg:5');
    expect(k.keyFor('pkg:5'), first);
    expect(k.keyFor('pkg:5'), first);
  });

  test('бошқа ният (ўлчам/режа) — бошқа калит', () {
    final k = make();
    expect(k.keyFor('pkg:5'), isNot(k.keyFor('pkg:10')));
  });

  test('ният тугагач (settled) кейинги уриниш янги калит олади', () {
    final k = make();
    final first = k.keyFor('submit');
    k.settled('submit');
    expect(k.keyFor('submit'), isNot(first));
  });

  test('settled бошқа ниятларга тегмайди; clear ҳаммасини тозалайди', () {
    final k = make();
    final a = k.keyFor('a');
    final b = k.keyFor('b');
    k.settled('a');
    expect(k.keyFor('b'), b);
    k.clear();
    expect(k.keyFor('b'), isNot(b));
    expect(a, isNotEmpty);
  });

  test('одатий генератор яроқли UUID беради (сервер талаби: 8–64 белги)', () {
    final key = IdempotencyKeys().keyFor('x');
    expect(RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(key), isTrue);
  });
}
