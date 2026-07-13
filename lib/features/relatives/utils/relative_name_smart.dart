import '../../../models/relative_person.dart';

/// Исм қисмлари + орфография / ўхшашлик.
class RelativeNameParts {
  const RelativeNameParts({
    this.firstName = '',
    this.lastName = '',
    this.patronymic = '',
  });

  final String firstName;
  final String lastName;
  final String patronymic;

  /// Кўрсатиш: Фамилия Исм Шариф (бўшларсиз).
  String get displayFullName {
    final parts = <String>[
      if (lastName.trim().isNotEmpty) lastName.trim(),
      if (firstName.trim().isNotEmpty) firstName.trim(),
      if (patronymic.trim().isNotEmpty) patronymic.trim(),
    ];
    return parts.join(' ');
  }
}

abstract final class RelativeNameSmart {
  /// Эски `fullName` ни қисмларга ажратиш (исм, фамилия, шариф).
  static RelativeNameParts splitLegacy(String fullName) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return const RelativeNameParts();
    if (parts.length == 1) {
      return RelativeNameParts(firstName: parts[0]);
    }
    if (parts.length == 2) {
      // «Фамилия Исм» ёки «Исм Фамилия» — биринчисини исм deb оламиз
      // (форма тартиби: исм → фамилия). Эски ёзувлар учун: 1=исм, 2=фамилия.
      return RelativeNameParts(firstName: parts[0], lastName: parts[1]);
    }
    return RelativeNameParts(
      firstName: parts[0],
      lastName: parts[1],
      patronymic: parts.sublist(2).join(' '),
    );
  }

  static RelativeNameParts fromPerson(RelativePerson p) {
    if (p.firstName.trim().isNotEmpty ||
        p.lastName.trim().isNotEmpty ||
        p.patronymic.trim().isNotEmpty) {
      return RelativeNameParts(
        firstName: p.firstName,
        lastName: p.lastName,
        patronymic: p.patronymic,
      );
    }
    return splitLegacy(p.fullName);
  }

  static String compose({
    required String firstName,
    required String lastName,
    String patronymic = '',
  }) =>
      RelativeNameParts(
        firstName: firstName,
        lastName: lastName,
        patronymic: patronymic,
      ).displayFullName;

  /// Солиштириш учун нормаллаш (ўхшаш ҳарфлар бирлашади).
  static String normalize(String raw) {
    var s = raw.trim().toLowerCase();
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    const map = <String, String>{
      'қ': 'к',
      'ғ': 'г',
      'ҳ': 'х',
      'ў': 'у',
      'ъ': '',
      'ь': '',
      'ё': 'е',
      'й': 'и',
      'ц': 'с',
      'щ': 'ш',
      'ә': 'а',
      'ө': 'о',
      'ү': 'у',
      'ң': 'н',
      // latin ≈ cyrillic common folds
      'q': 'к',
      'gʻ': 'г',
      "g'": 'г',
      'oʻ': 'у',
      "o'": 'у',
      'h': 'х',
      'sh': 'ш',
      'ch': 'ч',
      'ng': 'нг',
    };
    for (final e in map.entries) {
      s = s.replaceAll(e.key, e.value);
    }
    // Қолган лотин → яқин кирилл (оддий)
    const lat = {
      'a': 'а',
      'b': 'б',
      'd': 'д',
      'e': 'е',
      'f': 'ф',
      'g': 'г',
      'i': 'и',
      'j': 'ж',
      'k': 'к',
      'l': 'л',
      'm': 'м',
      'n': 'н',
      'o': 'о',
      'p': 'п',
      'r': 'р',
      's': 'с',
      't': 'т',
      'u': 'у',
      'v': 'в',
      'x': 'х',
      'y': 'й',
      'z': 'з',
      'w': 'в',
      'c': 'с',
    };
    final buf = StringBuffer();
    for (final ch in s.split('')) {
      buf.write(lat[ch] ?? ch);
    }
    return buf.toString().replaceAll(RegExp(r'[^а-яё0-9 ]'), '');
  }

  static int levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final m = a.length;
    final n = b.length;
    var prev = List<int>.generate(n + 1, (j) => j);
    var cur = List<int>.filled(n + 1, 0);
    for (var i = 1; i <= m; i++) {
      cur[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = [
          prev[j] + 1,
          cur[j - 1] + 1,
          prev[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      final tmp = prev;
      prev = cur;
      cur = tmp;
    }
    return prev[n];
  }

  /// 0..1 — 1 = бир хил.
  static double similarity(String a, String b) {
    final na = normalize(a);
    final nb = normalize(b);
    if (na.isEmpty && nb.isEmpty) return 1;
    if (na.isEmpty || nb.isEmpty) return 0;
    if (na == nb) return 1;
    final dist = levenshtein(na, nb);
    final maxLen = na.length > nb.length ? na.length : nb.length;
    return 1.0 - (dist / maxLen);
  }

  /// Тўлиқ исм ўхшашлиги (қисмлар алоҳида ҳам текширилади).
  static double personNameSimilarity(RelativeNameParts a, RelativeNameParts b) {
    final full = similarity(a.displayFullName, b.displayFullName);
    final first = similarity(a.firstName, b.firstName);
    final last = (a.lastName.isEmpty || b.lastName.isEmpty)
        ? 1.0
        : similarity(a.lastName, b.lastName);
    // Исм асосий; фамилия бор бўлса ҳам ҳисобга олинади.
    if (a.lastName.isEmpty && b.lastName.isEmpty) {
      return full > first ? full : first;
    }
    return (full * 0.35) + (first * 0.4) + (last * 0.25);
  }

  static const double suggestThreshold = 0.78;
  static const double mergeThreshold = 0.88;

  static List<({RelativePerson person, double score})> findSimilarPeople({
    required RelativeNameParts query,
    required List<RelativePerson> people,
    String? excludeId,
    double minScore = suggestThreshold,
  }) {
    final out = <({RelativePerson person, double score})>[];
    for (final p in people) {
      if (excludeId != null && p.id == excludeId) continue;
      if (p.isSelf) continue;
      final score = personNameSimilarity(query, fromPerson(p));
      if (score >= minScore) {
        out.add((person: p, score: score));
      }
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  /// Ўхшаш исм гуруҳлари (fuzzy dedup).
  static List<List<T>> fuzzyGroups<T>({
    required List<T> items,
    required String Function(T) nameOf,
    required DateTime? Function(T) birthOf,
    required String Function(T) genderOf,
    double minScore = mergeThreshold,
  }) {
    final n = items.length;
    final parent = List<int>.generate(n, (i) => i);
    int find(int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    }

    void union(int a, int b) {
      final ra = find(a);
      final rb = find(b);
      if (ra != rb) parent[rb] = ra;
    }

    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final sa = similarity(nameOf(items[i]), nameOf(items[j]));
        if (sa < minScore) continue;
        final bi = birthOf(items[i]);
        final bj = birthOf(items[j]);
        if (bi != null && bj != null) {
          final sameDay = bi.year == bj.year &&
              bi.month == bj.month &&
              bi.day == bj.day;
          if (!sameDay) continue;
        }
        final gi = genderOf(items[i]).trim();
        final gj = genderOf(items[j]).trim();
        if (gi.isNotEmpty && gj.isNotEmpty && gi != gj) continue;
        union(i, j);
      }
    }

    final buckets = <int, List<T>>{};
    for (var i = 0; i < n; i++) {
      buckets.putIfAbsent(find(i), () => []).add(items[i]);
    }
    return buckets.values.where((g) => g.length > 1).toList(growable: false);
  }
}
