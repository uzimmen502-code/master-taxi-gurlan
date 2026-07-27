import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/core/utils/fair_mix.dart';

void main() {
  group('FairMix.roundRobin', () {
    test('interleaves two sources 1:1', () {
      expect(
        FairMix.roundRobin([
          [1, 2, 3],
          [10, 20, 30],
        ]),
        [1, 10, 2, 20, 3, 30],
      );
    });

    test('continues when one source ends', () {
      expect(
        FairMix.roundRobin([
          ['a'],
          ['x', 'y', 'z'],
        ]),
        ['a', 'x', 'y', 'z'],
      );
    });

    test('three sources', () {
      expect(
        FairMix.roundRobin([
          ['b1', 'b2'],
          ['f1', 'f2'],
          ['p1'],
        ]),
        ['b1', 'f1', 'p1', 'b2', 'f2'],
      );
    });
  });

  group('FairMix.byScoreThenFair', () {
    test('higher score first; equal score fair by lane', () {
      final items = [
        (lane: 'a', score: 10, id: 1),
        (lane: 'b', score: 50, id: 2),
        (lane: 'a', score: 50, id: 3),
        (lane: 'b', score: 10, id: 4),
      ];
      final out = FairMix.byScoreThenFair(
        items,
        (e) => e.score,
        laneKey: (e) => e.lane,
      );
      expect(out.map((e) => e.id).toList(), [2, 3, 1, 4]);
    });
  });
}
