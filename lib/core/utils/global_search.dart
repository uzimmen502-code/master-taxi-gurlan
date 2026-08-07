import '../../models/search_index_entry.dart';
import 'catalog_search.dart';

/// Глобал қидирув: CatalogSearch + intent boost + geo.
class GlobalSearch {
  GlobalSearch._();

  static const _intentTaxi = {
    'такси',
    'taxi',
    'таксига',
    'йўловчи',
    'шаҳарлараро',
    'шахарлараро',
    'маршрут',
    'маҳаллий',
    'махаллий',
  };
  static const _intentJob = {
    'иш',
    'ish',
    'вакансия',
    'vakansiya',
    'эълон',
    'elon',
    'лаборант',
    'laborant',
  };
  static const _intentBread = {'нон', 'non', 'патир', 'patir', 'чўрек', 'chorek'};
  static const _intentFood = {'овқат', 'ovqat', 'таом', 'taom', 'кафе', 'kafe'};
  static const _intentShop = {
    'дўкон',
    'dukon',
    'магазин',
    'лабо',
    'labo',
    'бозор',
    'bozor',
  };
  static const _intentYuk = {'юк', 'yuk', 'грузь', 'груз'};
  static const _intentLocal = {
    'мфй',
    'mfy',
    'маҳалла',
    'махалла',
    'mahalla',
  };

  static final _wordSplit =
      RegExp(r"[^0-9a-zA-Zа-яёўқғҳА-ЯЁЎҚҒҲʻʼ']+", unicode: true);

  /// Нормаллаштирилган сўров токенлари (P2 array-contains учун ҳам).
  static List<String> queryTokens(String query) {
    return CatalogSearch.normalize(query)
        .split(_wordSplit)
        .map((w) => w.trim().toLowerCase())
        .where((w) => w.length >= 2)
        .toList(growable: false);
  }

  static List<String> _queryWords(String query) => queryTokens(query);

  static bool _hasAny(Set<String> words, Set<String> intent) {
    for (final w in words) {
      if (intent.contains(w)) return true;
      for (final i in intent) {
        if (w.contains(i) || i.contains(w)) return true;
      }
    }
    return false;
  }

  /// Релевантлик балли (каттароқ = юқорироқ).
  /// Stem-only / заиф ўхшашлик → 0 (натижага чиқмайди).
  static int score(SearchIndexEntry e, String query) {
    final q = CatalogSearch.normalize(query);
    if (q.isEmpty) return 0;

    final fields = <String>[
      e.title,
      e.subtitle,
      e.from,
      e.to,
      ...e.keywords,
      ...e.searchTokens,
    ];

    final matched = CatalogSearch.matches(q, fields);
    final base = CatalogSearch.score(
      q,
      title: e.title,
      extra: [
        e.subtitle,
        if (e.price != null) '${e.price}',
        e.from,
        e.to,
        ...e.keywords,
        ...e.searchTokens,
      ],
    );

    // Gate: кучли мос ёки matches; stem-only йўқ
    if (!matched && base < CatalogSearch.strongMatchMin) return 0;
    if (base <= 0) return 0;

    var s = base + e.priorityBoost;

    final words = _queryWords(q).toSet();
    final type = e.type;
    final module = e.moduleId;

    if (_hasAny(words, _intentTaxi)) {
      if (type == SearchIndexEntry.typeIntercityRoute ||
          module == 'intercity' ||
          module == 'local_taxi' ||
          module == 'marshrut') {
        s += 120;
      }
      if (module == 'yuk_birja') s += 40;
    }
    if (_hasAny(words, _intentYuk)) {
      if (type == SearchIndexEntry.typeYukListing || module == 'yuk_birja') {
        s += 100;
      }
    }
    if (_hasAny(words, _intentJob)) {
      if (type == SearchIndexEntry.typeJob || module == 'jobs') s += 110;
    }
    if (_hasAny(words, _intentBread)) {
      if (type == SearchIndexEntry.typeBreadProduct || module == 'bread') {
        s += 100;
      }
    }
    if (_hasAny(words, _intentFood)) {
      if (type == SearchIndexEntry.typeFoodProduct || module == 'food') {
        s += 100;
      }
    }
    if (_hasAny(words, _intentLocal)) {
      if (type == SearchIndexEntry.typeLocalPlace || module == 'local_taxi') {
        s += 90;
      }
    }
    if (_hasAny(words, _intentShop)) {
      if (type == SearchIndexEntry.typePlatformProduct ||
          type == SearchIndexEntry.typeMarketAd ||
          module == 'platform' ||
          module == 'cheap_products_home') {
        s += 80;
      }
    }

    for (final w in words) {
      if (w.length < 3) continue;
      final from = CatalogSearch.normalize(e.from);
      final to = CatalogSearch.normalize(e.to);
      if (from.contains(w) || to.contains(w)) {
        s += 25;
        break;
      }
    }

    return s;
  }

  static List<SearchIndexEntry> rank(
    Iterable<SearchIndexEntry> pool,
    String query, {
    int limit = 40,
  }) {
    final q = CatalogSearch.normalize(query);
    if (q.isEmpty) return const [];
    final scored = <({SearchIndexEntry e, int s})>[];
    for (final e in pool) {
      if (!e.active) continue;
      final s = score(e, q);
      if (s > 0) scored.add((e: e, s: s));
    }
    scored.sort((a, b) {
      final byScore = b.s.compareTo(a.s);
      if (byScore != 0) return byScore;
      return a.e.title.compareTo(b.e.title);
    });
    return scored.take(limit).map((x) => x.e).toList(growable: false);
  }
}
