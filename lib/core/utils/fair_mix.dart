/// Бир неча манба рўйхатларини адолатли аралаштириш.
class FairMix {
  FairMix._();

  /// Round-robin: ҳар манбадан навбатма-навбат 1 та.
  /// Тугаган манба ўтказиб юборилади; қолганлари давом этади.
  static List<T> roundRobin<T>(List<List<T>> sources) {
    if (sources.isEmpty) return const [];
    final queues = [
      for (final s in sources)
        if (s.isNotEmpty) List<T>.from(s),
    ];
    if (queues.isEmpty) return const [];
    if (queues.length == 1) return List<T>.from(queues.first);

    final out = <T>[];
    var i = 0;
    while (queues.isNotEmpty) {
      final q = queues[i];
      out.add(q.removeAt(0));
      if (q.isEmpty) {
        queues.removeAt(i);
        if (queues.isEmpty) break;
        i = i % queues.length;
      } else {
        i = (i + 1) % queues.length;
      }
    }
    return out;
  }

  /// Қидирув: score каттароқ биринчи; тенг score да манбалар RR.
  /// [scoreOf] каттароқ = яхшироқ.
  static List<T> byScoreThenFair<T>(
    List<T> items,
    int Function(T) scoreOf, {
    Object Function(T)? laneKey,
  }) {
    if (items.length <= 1) return List<T>.from(items);

    final keyed = laneKey ?? ((T _) => 0);
    final byScore = <int, List<T>>{};
    for (final item in items) {
      byScore.putIfAbsent(scoreOf(item), () => <T>[]).add(item);
    }
    final scores = byScore.keys.toList()..sort((a, b) => b.compareTo(a));

    final out = <T>[];
    for (final s in scores) {
      final bucket = byScore[s]!;
      if (bucket.length == 1 || laneKey == null) {
        out.addAll(bucket);
        continue;
      }
      // Тенг score — манба бўйича RR
      final lanes = <Object, List<T>>{};
      for (final item in bucket) {
        lanes.putIfAbsent(keyed(item), () => <T>[]).add(item);
      }
      out.addAll(roundRobin(lanes.values.toList(growable: false)));
    }
    return out;
  }
}
