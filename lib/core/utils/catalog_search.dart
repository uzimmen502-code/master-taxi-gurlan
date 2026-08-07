import '../../features/ads/utils/ad_search_text.dart';
import '../../models/platform_product.dart';

/// Платформа дўкони / онлайн бозор / эълонлар / глобал қидирув.
///
/// Фильтр: AND токенлар + кирилл ↔ лотин.
/// Жойлаштириш (каттароқ = юқорироқ):
/// 1 exact title · 2 whole word · 3 prefix (+ morph) · 4 morph stem ·
/// 5 compound · 6 extra fields.
///
/// Stem-only / умумий ҳарфлар (такси↔таклиф) — натижа эмас.
class CatalogSearch {
  CatalogSearch._();

  static const wExact = 1000;
  static const wWholeWord = 800;
  static const wPrefix = 600;
  static const wStem = 400;
  static const wCompound = 250;
  static const wExtra = 100;

  /// Кучли мослик пасти (prefix ва ундан юқори) — gate учун.
  static const strongMatchMin = wPrefix;

  static const _wExact = wExact;
  static const _wWholeWord = wWholeWord;
  static const _wPrefix = wPrefix;
  static const _wStem = wStem;
  static const _wCompound = wCompound;
  static const _wExtra = wExtra;

  /// Қисқа morph / дериват суффикслари (кирилл + лотин).
  static const _morphSuffixes = <String>{
    'чи',
    'ли',
    'лик',
    'лар',
    'га',
    'да',
    'ни',
    'дан',
    'нинг',
    'хона',
    'вой',
    'вор',
    'каш',
    'кор',
    'чилар',
    'ликлар',
    'chi',
    'li',
    'lik',
    'lar',
    'ga',
    'da',
    'ni',
    'dan',
    'ning',
    'xona',
    'voy',
    'vor',
    'kash',
    'kor',
    'chilar',
    'liklar',
  };

  static final _wordSplit =
      RegExp(r"[^0-9a-zA-Zа-яёўқғҳА-ЯЁЎҚҒҲʻʼ']+", unicode: true);

  static String normalize(String s) => s.trim().toLowerCase().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );

  static List<String> _words(String text) {
    return normalize(text)
        .split(_wordSplit)
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toList(growable: false);
  }

  static Set<String> _scriptForms(String token) {
    final t = token.trim().toLowerCase();
    if (t.isEmpty) return const {};
    return {
      t,
      AdSearchText.toLatin(t),
      AdSearchText.toCyrillic(t),
    }.where((x) => x.isNotEmpty).toSet();
  }

  static int _commonPrefixLen(String a, String b) {
    final n = a.length < b.length ? a.length : b.length;
    var i = 0;
    while (i < n && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    return i;
  }

  /// [wf] сўров [qf] дан morph/prefix даражада ўсадими?
  static bool isMorphExtension(String queryForm, String wordForm) {
    final qf = queryForm.trim().toLowerCase();
    final wf = wordForm.trim().toLowerCase();
    if (qf.isEmpty || wf.isEmpty) return false;
    if (qf == wf) return true;
    if (!wf.startsWith(qf) || wf.length <= qf.length) return false;
    final rest = wf.substring(qf.length);
    if (_morphSuffixes.contains(rest)) return true;
    for (final s in _morphSuffixes) {
      if (rest.startsWith(s)) return true;
    }
    return false;
  }

  /// Умумий илдиз фақат morph/prefix билан ва мин. 4 ҳарф.
  static bool isValidatedStem(String queryForm, String wordForm) {
    final qf = queryForm.trim().toLowerCase();
    final wf = wordForm.trim().toLowerCase();
    if (qf.length < 2 || wf.length < 2) return false;
    if (qf == wf) return true;
    if (isMorphExtension(qf, wf)) return true;
    // Умумий илдиз: мин 4 + morph қолдиқ (ёлғон такси/таклиф ёпилади)
    final rootLen = _commonPrefixLen(qf, wf);
    if (rootLen < 4) return false;
    if (rootLen < (qf.length * 0.6).ceil()) return false;
    final root = qf.substring(0, rootLen);
    return isMorphExtension(root, wf);
  }

  /// [fields] ичида барча сўров сўзлари кучли мос келса true.
  /// Substring-contains эмас — whole / prefix / morph.
  static bool matches(String query, Iterable<String> fields) {
    final q = normalize(query);
    if (q.isEmpty) return true;
    final tokens = q.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return true;

    final fieldWords = <String>[];
    for (final f in fields) {
      final n = normalize(f.trim());
      if (n.isEmpty) continue;
      fieldWords.addAll(_words(n));
      fieldWords.addAll(_words(AdSearchText.toLatin(n)));
      fieldWords.addAll(_words(AdSearchText.toCyrillic(n)));
    }
    if (fieldWords.isEmpty) return false;

    for (final t in tokens) {
      final forms = _scriptForms(t);
      var ok = false;
      for (final qf in forms) {
        for (final word in fieldWords) {
          final wForms = _scriptForms(word);
          for (final wf in wForms) {
            if (qf == wf || isValidatedStem(qf, wf) || isMorphExtension(qf, wf)) {
              ok = true;
              break;
            }
          }
          if (ok) break;
        }
        if (ok) break;
      }
      if (!ok) return false;
    }
    return true;
  }

  static bool matchesProduct(PlatformProduct p, String query) {
    return matches(query, [
      p.name,
      p.description,
      p.unit,
      '${p.price}',
      p.id,
    ]);
  }

  /// Бир токеннинг ном сўзларига энг яхши мослиги (0 = йўқ).
  static int _bestTitleTokenScore(String token, List<String> titleWords) {
    final qForms = _scriptForms(token);
    if (qForms.isEmpty) return 0;

    var best = 0;
    for (final word in titleWords) {
      final wForms = _scriptForms(word);
      for (final qf in qForms) {
        for (final wf in wForms) {
          if (qf.isEmpty || wf.isEmpty) continue;
          if (qf == wf) {
            best = best < _wWholeWord ? _wWholeWord : best;
            continue;
          }
          // Фақат morph/дериват префикс (нон→нонвой, такси→таксичи).
          // Оддий startsWith йўқ — иш→ишонч (ish…) ёлғонларини ёпади.
          if (isMorphExtension(qf, wf)) {
            best = best < _wPrefix ? _wPrefix : best;
            continue;
          }
          if (isValidatedStem(qf, wf)) {
            best = best < _wStem ? _wStem : best;
            continue;
          }
          if (qf.length >= 4 && wf.contains(qf) && !wf.startsWith(qf)) {
            best = best < _wCompound ? _wCompound : best;
          }
        }
      }
    }
    return best;
  }

  static bool _hayHasStrong(String hayWordsJoined, Set<String> forms) {
    final words = _words(hayWordsJoined);
    for (final qf in forms) {
      for (final w in words) {
        for (final wf in _scriptForms(w)) {
          if (qf == wf || isMorphExtension(qf, wf) || isValidatedStem(qf, wf)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Каттароқ = яхшироқ. Мос келмаса 0 (stem-only / weak йўқ).
  /// Барча сўров токенлари мос келиши шарт (AND).
  static int score(
    String query, {
    required String title,
    Iterable<String> extra = const [],
  }) {
    final q = normalize(query);
    if (q.isEmpty) return 0;

    final titleN = normalize(title);
    final titleWords = _words(titleN);
    final titleForms = _scriptForms(titleN);
    final qForms = _scriptForms(q);

    var s = 0;

    if (qForms.any(titleForms.contains)) {
      s += _wExact;
    }

    final extraJoined = normalize(
      extra.map((e) => e.trim()).where((e) => e.isNotEmpty).join(' '),
    );
    final titleHay =
        '$titleN ${AdSearchText.toLatin(titleN)} ${AdSearchText.toCyrillic(titleN)}';
    final extraHay =
        '$extraJoined ${AdSearchText.toLatin(extraJoined)} ${AdSearchText.toCyrillic(extraJoined)}';

    final tokens = q.split(' ').where((t) => t.isNotEmpty).toList();
    var titleTokenHits = 0;

    for (final t in tokens) {
      final forms = _scriptForms(t);
      final titleHit = _bestTitleTokenScore(t, titleWords);
      if (titleHit > 0) {
        s += titleHit;
        titleTokenHits++;
        continue;
      }
      if (_hayHasStrong(titleHay, forms)) {
        s += _wCompound;
        titleTokenHits++;
        continue;
      }
      if (_hayHasStrong(extraHay, forms)) {
        s += _wExtra;
        continue;
      }
      // Бирор токен мос келмаса — бутун сўров номос (AND)
      return 0;
    }

    if (s <= 0) return 0;

    s += titleTokenHits * 10;
    s += (200 - titleN.length.clamp(0, 200));
    return s;
  }

  static int scoreProduct(PlatformProduct p, String query) {
    return score(
      query,
      title: p.name,
      extra: [p.description, p.unit, '${p.price}'],
    );
  }

  static int compare(
    String query, {
    required String titleA,
    required String titleB,
    Iterable<String> extraA = const [],
    Iterable<String> extraB = const [],
    int Function()? tieBreak,
  }) {
    final byScore = score(query, title: titleB, extra: extraB)
        .compareTo(score(query, title: titleA, extra: extraA));
    if (byScore != 0) return byScore;
    return tieBreak?.call() ?? 0;
  }
}
