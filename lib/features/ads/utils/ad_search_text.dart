/// Нормализация ва қидирув токенлари (кирилл ↔ лотин) — Арзон маҳсулотлар.
class AdSearchText {
  AdSearchText._();

  static const maxTokens = 48;
  static const minTokenLen = 2;

  static final _wordSplit =
      RegExp(r"[^0-9a-zA-Zа-яёўқғҳА-ЯЁЎҚҒҲʻʼ']+", unicode: true);

  static bool isCyrillic(String s) =>
      s.runes.any((r) => r >= 0x0400 && r <= 0x04FF);

  /// oʻ / gʻ / `'` / ‘’ — ASCII `'` (кирилл ў/ғ диграфлари учун).
  static String foldMarks(String s) {
    return s.toLowerCase().replaceAll(
          RegExp('[\u02BB\u02BC\u02BD\u02C8\u0060\u00B4\u2018\u2019\u2032]'),
          "'",
        );
  }

  static String toLatin(String s) {
    const map = {
      'а': 'a',
      'б': 'b',
      'в': 'v',
      'г': 'g',
      'д': 'd',
      'е': 'e',
      'ё': 'yo',
      'ж': 'j',
      'з': 'z',
      'и': 'i',
      'й': 'y',
      'к': 'k',
      'л': 'l',
      'м': 'm',
      'н': 'n',
      'о': 'o',
      'п': 'p',
      'р': 'r',
      'с': 's',
      'т': 't',
      'у': 'u',
      'ф': 'f',
      'х': 'x',
      'ц': 'ts',
      'ч': 'ch',
      'ш': 'sh',
      'щ': 'sh',
      'ъ': '',
      'ы': 'i',
      'ь': '',
      'э': 'e',
      'ю': 'yu',
      'я': 'ya',
      'ҳ': 'h',
      'қ': 'q',
      'ғ': "g'",
      'ў': "o'",
      'ң': 'ng',
    };
    final buf = StringBuffer();
    for (final c in foldMarks(s).split('')) {
      buf.write(map[c] ?? c);
    }
    return buf.toString();
  }

  static String toCyrillic(String s) {
    var result = foldMarks(s);
    const digraphs = {
      'sh': 'ш',
      'ch': 'ч',
      'yo': 'ё',
      'yu': 'ю',
      'ya': 'я',
      'ts': 'ц',
      'ng': 'ң',
      "o'": 'ў',
      "g'": 'ғ',
      'ʻ': '',
      'ʼ': '',
    };
    for (final e in digraphs.entries) {
      result = result.replaceAll(e.key, e.value);
    }
    const singles = {
      'q': 'қ',
      'h': 'ҳ',
      'a': 'а',
      'b': 'б',
      'v': 'в',
      'g': 'г',
      'd': 'д',
      'e': 'е',
      'j': 'ж',
      'z': 'з',
      'i': 'и',
      'y': 'й',
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
      'f': 'ф',
      'x': 'х',
    };
    final buf = StringBuffer();
    for (final c in result.split('')) {
      buf.write(singles[c] ?? c);
    }
    return buf.toString();
  }

  static List<String> _words(String text) {
    return text
        .toLowerCase()
        .split(_wordSplit)
        .map((w) => w.trim())
        .where((w) => w.length >= minTokenLen)
        .toList(growable: false);
  }

  /// Эълон учун Firestore `searchTokens`.
  static List<String> buildTokens(String title, String description) {
    final out = <String>{};
    void addWord(String w) {
      if (w.length < minTokenLen) return;
      out.add(w);
      final latin = toLatin(w);
      final cyrl = toCyrillic(w);
      if (latin.length >= minTokenLen) out.add(latin);
      if (cyrl.length >= minTokenLen) out.add(cyrl);
    }

    for (final w in _words('$title $description')) {
      addWord(w);
      if (out.length >= maxTokens) break;
    }
    return out.take(maxTokens).toList(growable: false);
  }

  /// Қидирув сўрови токенлари (ҳар икки скрипт).
  static List<String> queryTokens(String query) {
    final q = query.trim().toLowerCase();
    if (q.length < minTokenLen) return const [];
    final out = <String>{};
    for (final w in _words(q)) {
      out.add(w);
      out.add(toLatin(w));
      out.add(toCyrillic(w));
    }
    // Бутун сўров ҳам (бир сўзли)
    if (!_wordSplit.hasMatch(q.trim())) {
      out.add(q);
      out.add(toLatin(q));
      out.add(toCyrillic(q));
    }
    return out.where((t) => t.length >= minTokenLen).toList(growable: false);
  }

  static String _haystack(AdSearchable ad) {
    final parts = <String>[
      ad.titleLower,
      ad.description.toLowerCase(),
      ...ad.searchTokens,
    ];
    final joined = parts.join(' ');
    return '$joined ${toLatin(joined)} ${toCyrillic(joined)}';
  }

  /// Барча сўров сўзлари мос келса true (OR скриптлар орасида).
  static bool matches(AdSearchable ad, String query) {
    final q = query.trim().toLowerCase();
    if (q.length < minTokenLen) return true;
    final words = _words(q);
    if (words.isEmpty) return true;
    final hay = _haystack(ad);
    for (final w in words) {
      final latin = toLatin(w);
      final cyrl = toCyrillic(w);
      final ok = hay.contains(w) ||
          hay.contains(latin) ||
          hay.contains(cyrl) ||
          ad.searchTokens.contains(w) ||
          ad.searchTokens.contains(latin) ||
          ad.searchTokens.contains(cyrl);
      if (!ok) return false;
    }
    return true;
  }

  /// Релевантлик (каттароқ = яхшироқ).
  /// Эълон/каталог жойлаштириш учун [CatalogSearch.score] ишлатинг.
  static int score(AdSearchable ad, String query) {
    final q = query.trim().toLowerCase();
    if (q.length < minTokenLen) return 0;
    var s = 0;
    final title = ad.titleLower;
    final titleLat = toLatin(title);
    final titleCyr = toCyrillic(title);
    if (title.contains(q) ||
        titleLat.contains(toLatin(q)) ||
        titleCyr.contains(toCyrillic(q))) {
      s += 100;
    }
    final words = _words(q);
    for (final w in words) {
      final latin = toLatin(w);
      final cyrl = toCyrillic(w);
      if (title.contains(w) || title.contains(latin) || title.contains(cyrl)) {
        s += 40;
      } else if (ad.searchTokens.contains(w) ||
          ad.searchTokens.contains(latin) ||
          ad.searchTokens.contains(cyrl)) {
        s += 25;
      } else if (ad.description.toLowerCase().contains(w) ||
          toLatin(ad.description).contains(latin)) {
        s += 10;
      }
    }
    return s;
  }
}

/// Қидирув учун минимал майдонлар (AdModel ҳам шу шаклда).
abstract class AdSearchable {
  String get titleLower;
  String get description;
  List<String> get searchTokens;
}
