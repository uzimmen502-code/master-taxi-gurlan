import 'dart:async';

/// Иккита рўйхат оқимини бирлаштиради.
///
/// Нима учун керак: бош саҳифадаги ҳудудга боғлиқ бўлимлар икки манбадан
/// ўқийди — (1) `districtId` бўйича серверда филтрланган асосий сўров ва
/// (2) ҲУДУДСИЗ эски ёзувлар. Firestore'да «майдон йўқ» бўйича сўров
/// қилиб бўлмайди, шунинг учун эскилари алоҳида олиниб, клиентда
/// қўшилади — backfill қилингунча биронта ёзув йўқолиб кетмайди.
///
/// Иккала оқимдан ҳам биринчи жавоб келмагунча ҳеч нарса чиқарилмайди:
/// акс ҳолда рўйхат аввал қисқа кўриниб, кейин «сакраб» тўларди.
/// Такрорлар [idOf] бўйича олиб ташланади.
Stream<List<T>> mergeListStreams<T>(
  Stream<List<T>> primary,
  Stream<List<T>> secondary, {
  required String Function(T item) idOf,
}) {
  var listA = <T>[];
  var listB = <T>[];
  var seenA = false;
  var seenB = false;

  late StreamController<List<T>> controller;
  StreamSubscription<List<T>>? subA;
  StreamSubscription<List<T>>? subB;

  void emit() {
    if (!seenA || !seenB) return;
    final byId = <String, T>{};
    for (final item in [...listA, ...listB]) {
      byId[idOf(item)] = item;
    }
    if (!controller.isClosed) controller.add(byId.values.toList());
  }

  controller = StreamController<List<T>>(
    onListen: () {
      subA = primary.listen(
        (v) {
          listA = v;
          seenA = true;
          emit();
        },
        onError: controller.addError,
      );
      subB = secondary.listen(
        (v) {
          listB = v;
          seenB = true;
          emit();
        },
        onError: controller.addError,
      );
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
    },
  );

  return controller.stream;
}
