import 'dart:async';

/// Бир нечта саноқ оқимининг йиғиндиси — sidebar нишони учун.
///
/// «Улгуржи бозор» нишони икки коллекциядан йиғилади: тасдиқ кутаётган
/// сотувчилар (`wholesale_sellers`) ва тасдиқ кутаётган улгуржи
/// маҳсулотлар (`wholesale_products`). Лойиҳада rxdart йўқ, шунинг учун
/// қўлда: ҳар оқимнинг охирги қиймати сақланади, бири ўзгарса йиғинди
/// қайта чиқарилади. Ҳали қиймат бермаган оқим 0 деб олинади. Тинглаш
/// бекор қилинса — ички обуналар ҳам ёпилади (Firestore тингловчиси
/// осилиб қолмайди).
Stream<int> sumCountStreams(List<Stream<int>> streams) {
  if (streams.isEmpty) return Stream<int>.value(0);
  if (streams.length == 1) return streams.single;
  final subs = <StreamSubscription<int>>[];
  final last = List<int>.filled(streams.length, 0);
  late final StreamController<int> ctrl;
  ctrl = StreamController<int>(
    onListen: () {
      for (var i = 0; i < streams.length; i++) {
        subs.add(streams[i].listen(
          (v) {
            last[i] = v;
            ctrl.add(last.fold<int>(0, (a, b) => a + b));
          },
          onError: ctrl.addError,
        ));
      }
    },
    onCancel: () async {
      final pending = List<StreamSubscription<int>>.of(subs);
      subs.clear();
      await Future.wait(pending.map((s) => s.cancel()));
    },
  );
  return ctrl.stream;
}
