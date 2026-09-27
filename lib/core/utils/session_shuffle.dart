import 'dart:math';

/// Илова ҳар сафар очилганда рўйхатлар бошқа тартибда кўринсин учун —
/// битта сеанс уруғи.
///
/// Жараён давомида ўзгармайди, шунинг учун скролл ёки қайта қуриш
/// (rebuild) вақтида элементлар ўрни сакрамайди; илова ёпилиб қайта
/// очилганда эса янги уруғ олинади ва тартиб ўзгаради.
final int kSessionShuffleSeed = DateTime.now().microsecondsSinceEpoch;

/// Шу сеанс учун тасодифчи.
Random sessionRandom() => Random(kSessionShuffleSeed);

/// Янги келган элементларни аралаштириб қўшади, аввал кўрсатилганлар
/// тартибини эса ўзгартирмайди.
///
/// Шунинг учун рўйхат ўсганда (пагинация) ёки маълумот янгиланганда
/// фойдаланувчи кўриб турган элементлар жойидан сакрамайди.
List<T> mergeShuffled<T>({
  required List<T> current,
  required List<T> incoming,
  required String Function(T item) idOf,
  required Random random,
}) {
  final byId = <String, T>{for (final item in incoming) idOf(item): item};

  final kept = <T>[];
  final keptIds = <String>{};
  for (final old in current) {
    final id = idOf(old);
    final refreshed = byId[id];
    if (refreshed == null) continue; // энди рўйхатда йўқ
    kept.add(refreshed);
    keptIds.add(id);
  }

  final added = incoming.where((e) => !keptIds.contains(idOf(e))).toList()
    ..shuffle(random);

  return [...kept, ...added];
}
