import 'dart:async';

import 'package:ava_gurlan/features/admin_web/utils/count_stream_sum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sumCountStreams — «Улгуржи бозор» нишони', () {
    test('ҳар ўзгаришда охирги қийматлар йиғиндиси', () async {
      final sellers = StreamController<int>();
      final products = StreamController<int>();
      final out = <int>[];
      final sub = sumCountStreams([sellers.stream, products.stream])
          .listen(out.add);

      sellers.add(2); // маҳсулот оқими ҳали жим — 0 деб олинади
      await Future<void>.delayed(Duration.zero);
      products.add(3);
      await Future<void>.delayed(Duration.zero);
      sellers.add(0); // сотувчилар тасдиқланди
      await Future<void>.delayed(Duration.zero);

      expect(out, [2, 5, 3]);
      await sub.cancel();
      await sellers.close();
      await products.close();
    });

    test('бекор қилинганда ички обуналар ёпилади', () async {
      var cancelled = 0;
      StreamController<int> mk() => StreamController<int>(
            onCancel: () => cancelled++,
          );
      final a = mk();
      final b = mk();
      final sub = sumCountStreams([a.stream, b.stream]).listen((_) {});
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(cancelled, 2);
    });

    test('хато узатилади', () async {
      final a = StreamController<int>();
      final b = StreamController<int>();
      final errors = <Object>[];
      final sub = sumCountStreams([a.stream, b.stream])
          .listen((_) {}, onError: errors.add);
      a.addError(StateError('x'));
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(1));
      await sub.cancel();
    });

    test('битта оқим — ўзи; бўш рўйхат — 0', () async {
      expect(await sumCountStreams([Stream.value(4)]).first, 4);
      expect(await sumCountStreams(const []).first, 0);
    });
  });
}
