import 'dart:async';

/// Манба тингловчилари (Firestore `snapshots()` ва ҳ.к.) ФАҚАТ биринчи обуначи пайдо бўлганда очиладиган ва
/// охиргиси кетганда ёпиладиган broadcast оқим. Қайта обуна бўлса — [start] яна чақирилади.
///
/// Нима учун: аввал «Хабарлар» оқимлари тингловчиларни оқим ЯРАТИЛГАН заҳоти очарди. Экран оқимни `await`дан
/// кейин яратиб, StreamBuilder унга кейинги кадрда обуна бўларди — шу оралиқда (кешдан) келган биринчи жавобни
/// broadcast оқим ҳеч кимга бермай ташлаб юборар ва экран абадий «загрузка»да қоларди (эга, 2026-10-26:
/// «хабар келмаяпти, фақат загрузка»; аудит X-01). Яна: биринчи бекор қилишдан кейин оқим «ўлик» бўлиб қоларди.
///
/// [start] обунаси очилган манбаларни қайтаради; улар бекор қилишда ёпилади. [start] ичида `controller.add`
/// ни бемалол чақириш мумкин — обуначи аллақачон бор.
Stream<T> lazyBroadcastStream<T>(
  List<StreamSubscription<dynamic>> Function(StreamController<T> controller) start,
) {
  late final StreamController<T> controller;
  var subs = <StreamSubscription<dynamic>>[];
  controller = StreamController<T>.broadcast(
    onListen: () => subs = start(controller),
    onCancel: () async {
      final all = subs;
      subs = [];
      for (final s in all) {
        await s.cancel();
      }
    },
  );
  return controller.stream;
}
