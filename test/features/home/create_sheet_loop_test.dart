// «＋» → бўлим → орқага = «＋» менюси яна (эга, 2026-11-03: «фақат бир қадам орқага»).
import 'package:ava_gurlan/features/home/create_sheet_loop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('бўлимдан қайтилди — меню қайта очилади; меню ёпилса тўхтайди', () async {
    final results = [true, true, false]; // бўлим, бўлим, меню ёпилди
    var opened = 0;
    await runCreateSheetLoop(openOnce: () async => results[opened++], stillHere: () => true);
    expect(opened, 3);
  });

  test('бўлим очилмади (хабар / дарвоза / меню ёпилди) — меню қайта ЧИҚМАЙДИ', () async {
    var opened = 0;
    await runCreateSheetLoop(openOnce: () async {
      opened++;
      return false;
    }, stillHere: () => true);
    expect(opened, 1);
  });

  test('бошқа экранга ўтилган (бош экран олдинда эмас) — меню чиқмайди', () async {
    var opened = 0;
    await runCreateSheetLoop(openOnce: () async {
      opened++;
      return true;
    }, stillHere: () => false);
    expect(opened, 1);
  });
}
