import '../../features/ads/utils/ad_search_text.dart';
import '../../models/platform_product.dart';

/// Платформа дўкони / онлайн бозор учун умумий қидирув.
/// AND токенлар + бўшлиқ нормализация + кирилл ↔ лотин.
class CatalogSearch {
  CatalogSearch._();

  static String normalize(String s) => s.trim().toLowerCase().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );

  /// [fields] ичида барча сўров сўзлари топилса true.
  static bool matches(String query, Iterable<String> fields) {
    final q = normalize(query);
    if (q.isEmpty) return true;
    final tokens = q.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return true;

    final joined = normalize(
      fields.map((f) => f.trim()).where((f) => f.isNotEmpty).join(' '),
    );
    final hay = '$joined ${AdSearchText.toLatin(joined)} ${AdSearchText.toCyrillic(joined)}';

    for (final t in tokens) {
      final latin = AdSearchText.toLatin(t);
      final cyrl = AdSearchText.toCyrillic(t);
      final ok = hay.contains(t) ||
          (latin.isNotEmpty && hay.contains(latin)) ||
          (cyrl.isNotEmpty && hay.contains(cyrl));
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

  /// Каттароқ = яхшироқ (номга тўғри келиш устун).
  static int score(String query, {required String title, Iterable<String> extra = const []}) {
    final q = normalize(query);
    if (q.isEmpty) return 0;
    var s = 0;
    final titleN = normalize(title);
    final titleLat = AdSearchText.toLatin(titleN);
    final titleCyr = AdSearchText.toCyrillic(titleN);
    final qLat = AdSearchText.toLatin(q);
    final qCyr = AdSearchText.toCyrillic(q);
    if (titleN.contains(q) || titleLat.contains(qLat) || titleCyr.contains(qCyr)) {
      s += 100;
    }
    final hay = normalize([title, ...extra].join(' '));
    final hayAll = '$hay ${AdSearchText.toLatin(hay)} ${AdSearchText.toCyrillic(hay)}';
    for (final t in q.split(' ').where((t) => t.isNotEmpty)) {
      final latin = AdSearchText.toLatin(t);
      final cyrl = AdSearchText.toCyrillic(t);
      if (titleN.contains(t) || titleN.contains(latin) || titleN.contains(cyrl)) {
        s += 40;
      } else if (hayAll.contains(t) || hayAll.contains(latin) || hayAll.contains(cyrl)) {
        s += 15;
      }
    }
    return s;
  }

  static int scoreProduct(PlatformProduct p, String query) {
    return score(
      query,
      title: p.name,
      extra: [p.description, p.unit, '${p.price}'],
    );
  }
}
