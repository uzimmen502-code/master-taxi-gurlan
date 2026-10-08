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
///
/// ҚАЙТА ТИНГЛАНАДИ (2026-10-08): ҳар бир тингловчи ўз ички обуналари ва
/// ўз йиғиндисини олади (`Stream.multi`). Аввал бу бир марталик
/// `StreamController` эди: сайдбар `ListView(children:)` экрандан чиққан
/// қаторни ўчириб, қайтганда ўша виджетдан қайта қуради — `StreamBuilder`
/// ўша оқимни иккинчи марта тинглаб `Bad state: Stream has already been
/// listened to.` отарди ва release'да «Улгуржи бозор» ўрнида катта кулранг
/// блок чиқиб, қолган бўлимлар йўқоларди (эга скриншоти).
///
/// ШАРТ: ички [streams] ҳам қайта тингланадиган бўлсин (broadcast) —
/// Firestore `snapshots()` ва уларнинг `.map()` и шундай (веб'да текширилган).
/// Бир марталик оқим берилса, иккинчи тингловчида ўша оқим хато беради.
Stream<int> sumCountStreams(List<Stream<int>> streams) {
  if (streams.isEmpty) return Stream<int>.value(0);
  if (streams.length == 1) return streams.single;
  return Stream<int>.multi((controller) {
    final last = List<int>.filled(streams.length, 0);
    final subs = <StreamSubscription<int>>[
      for (var i = 0; i < streams.length; i++)
        streams[i].listen(
          (v) {
            last[i] = v;
            controller.add(last.fold<int>(0, (a, b) => a + b));
          },
          onError: controller.addError,
        ),
    ];
    controller.onCancel = () =>
        Future.wait(subs.map((s) => s.cancel())).then((_) {});
  });
}
