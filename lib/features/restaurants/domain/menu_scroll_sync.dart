// Икки устунли боғланган меню (左右联动, §12.4) — СОФ ҳисоб-китоб.
//
// Ўнг рўйхат: ҳар категория учун ёпишқоқ сарлавҳа + қатъий баландликдаги
// таом қаторлари. Баландликлар қатъий бўлгани учун ҳар бўлимнинг бошланиш
// offset'и олдиндан маълум: скролл ўзгарганда фаол категория шу
// offset'лардан, категория босилганда эса скролл манзили шундан олинади.
// Қулф (lock) виджетда: босишдан кейинги анимация скролл ҳодисалари
// фаол категорияни қайта ўзгартирмасин.

class MenuScrollSync {
  MenuScrollSync({
    required List<int> sectionItemCounts,
    required this.headerHeight,
    required this.itemHeight,
  }) : sectionItemCounts = List.unmodifiable(sectionItemCounts) {
    var acc = 0.0;
    final offsets = <double>[];
    for (final n in this.sectionItemCounts) {
      offsets.add(acc);
      acc += headerHeight + n * itemHeight;
    }
    sectionOffsets = List.unmodifiable(offsets);
    totalHeight = acc;
  }

  final List<int> sectionItemCounts;
  final double headerHeight;
  final double itemHeight;

  /// Ҳар бўлим сарлавҳасининг бошланиш offset'и.
  late final List<double> sectionOffsets;

  /// Бутун рўйхат баландлиги.
  late final double totalHeight;

  int get sectionCount => sectionItemCounts.length;

  /// Скролл offset'ида қайси бўлим фаол (сарлавҳаси тепага етган охиргиси).
  int sectionAt(double offset) {
    if (sectionOffsets.isEmpty) return 0;
    var active = 0;
    for (var i = 0; i < sectionOffsets.length; i++) {
      // Кичик захира: анимация айнан чегарада тўхтаганда ҳам кейингиси ёнсин.
      if (offset + 0.5 >= sectionOffsets[i]) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }

  /// Бўлимдаги [index]-таом ёпишқоқ сарлавҳанинг ТЎҒРИДАН остида турадиган offset (бўлимнинг ўзи сарлавҳа
  /// остида қолади). Индекс бўлим чегарасига қисилади; [maxScrollExtent] дан ошмайди.
  double offsetOfItem(int section, int index, {double? maxScrollExtent}) {
    if (sectionOffsets.isEmpty) return 0;
    final s = section.clamp(0, sectionOffsets.length - 1);
    final count = sectionItemCounts[s];
    final i = count <= 0 ? 0 : index.clamp(0, count - 1);
    final o = sectionOffsets[s] + i * itemHeight;
    if (maxScrollExtent == null) return o;
    return o > maxScrollExtent ? maxScrollExtent : o;
  }

  /// Бўлим сарлавҳасини тепага келтирадиган offset; [maxScrollExtent] дан
  /// ошмайди (охирги қисқа бўлимлар учун).
  double offsetOf(int section, {double? maxScrollExtent}) {
    if (sectionOffsets.isEmpty) return 0;
    final i = section.clamp(0, sectionOffsets.length - 1);
    final o = sectionOffsets[i];
    if (maxScrollExtent == null) return o;
    return o > maxScrollExtent ? maxScrollExtent : o;
  }
}
