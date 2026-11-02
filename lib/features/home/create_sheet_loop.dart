/// «＋» менюси: бўлимдан ОРҚАГА қайтилса меню қайта очилади — «фақат бир қадам орқага»
/// (эга, 2026-11-03). [openOnce] — менюни кўрсатиб, танланган бўлимни очади; бўлим очилиб,
/// ундан қайтилганда `true`, меню ёпилса / бўлим очилмаса (хабар, дарвоза) — `false`.
/// [stillHere] — бош экран ҳали олдинда (бошқа экранга ўтилган бўлса меню кўрсатилмайди).
Future<void> runCreateSheetLoop({
  required Future<bool> Function() openOnce,
  required bool Function() stillHere,
}) async {
  while (await openOnce()) {
    if (!stillHere()) break;
  }
}
