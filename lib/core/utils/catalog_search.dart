import '../../features/ads/utils/ad_search_text.dart';
import '../../models/platform_product.dart';

/// Платформа дўкони / онлайн бозор / эълонлар учун умумий қидирув.
///
/// Фильтр: AND токенлар + кирилл ↔ лотин.
/// Жойлаштириш (каттароқ = юқорироқ):
/// 1 exact title · 2 whole word · 3 prefix · 4 stem/affix ·
/// 5 compound · 6 extra fields · 7 weak contains ·
/// тенгликда: кўпроқ номдаги токен · қисқароқ ном.
class CatalogSearch {
  CatalogSearch._();

  static const _wExact = 1000;
  static const _wWholeWord = 800;
  static const _wPrefix = 600;
  static const _wStem = 400;
  static const _wCompound = 250;
  static const _wExtra = 100;
  static const _wWeak = 40;

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

  /// [fields] ичида барча сўров сўзлари топилса true.
  static bool matches(String query, Iterable<String> fields) {
    final q = normalize(query);
    if (q.isEmpty) return true;
    final tokens = q.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return true;

    final joined = normalize(
      fields.map((f) => f.trim()).where((f) => f.isNotEmpty).join(' '),
    );
    final hay =
        '$joined ${AdSearchText.toLatin(joined)} ${AdSearchText.toCyrillic(joined)}';

    for (final t in tokens) {
      final forms = _scriptForms(t);
      final ok = forms.any(hay.contains);
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
          // Префикс: сўз сўров билан бошланади (Нон → Нонли)
          if (qf.length >= 2 && wf.startsWith(qf)) {
            best = best < _wPrefix ? _wPrefix : best;
            continue;
          }
          // Stem/affix: сўров сўз ildизидан ўсади (нон → нончи сўрови)
          if (wf.length >= 3 && qf.startsWith(wf) && qf.length > wf.length) {
            best = best < _wStem ? _wStem : best;
            continue;
          }
          // Умумий ildиз (мин. 3): нонлар / нонвой
          final rootLen = _commonPrefixLen(qf, wf);
          if (rootLen >= 3 && rootLen >= (qf.length * 0.6).ceil()) {
            best = best < _wStem ? _wStem : best;
            continue;
          }
          // Бирикма ичида
          if (qf.length >= 3 && wf.contains(qf) && !wf.startsWith(qf)) {
            best = best < _wCompound ? _wCompound : best;
          }
        }
      }
    }
    return best;
  }

  static int _commonPrefixLen(String a, String b) {
    final n = a.length < b.length ? a.length : b.length;
    var i = 0;
    while (i < n && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    return i;
  }

  static bool _hayHasAny(String hay, Set<String> forms) {
    for (final f in forms) {
      if (f.isNotEmpty && hay.contains(f)) return true;
    }
    return false;
  }

  /// Каттароқ = яхшироқ (номга тўғри келиш устун).
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

    // 1) Аниқ ном = сўров
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
      // Ном ичида заиф (сўз бўлинмаган бирикма)
      if (_hayHasAny(titleHay, forms)) {
        s += forms.any((f) => f.length >= 3) ? _wCompound : _wWeak;
        titleTokenHits++;
        continue;
      }
      // 6) Фақат тавсиф/бошқа майдон
      if (_hayHasAny(extraHay, forms)) {
        s += _wExtra;
        continue;
      }
      // 7) Заиф — matches() аллақачон ўтказган бўлиши мумкин
      s += _wWeak;
    }

    // Тенглик: кўпроқ ном токенлари, кейин қисқароқ ном
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

  /// score каттароқ биринчи; тенг бўлса [tieBreak] (мас. янгилик).
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
