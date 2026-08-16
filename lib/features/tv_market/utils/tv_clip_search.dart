import '../../../core/utils/catalog_search.dart';
import '../../ads/utils/ad_search_text.dart';
import '../models/tv_clip.dart';

/// ТВ маркет қидируви: CatalogSearch + 3 тил (uz_Cyrl / uz_Latn / ru).
class TvClipSearch {
  TvClipSearch._();

  static const resultLimit = 48;
  static const poolLimit = 400;
  static const tokenQueryLimit = 80;

  static const _productLabels = <String>[
    'маҳсулот',
    'mahsulot',
    'товар',
    'tovar',
    'product',
  ];

  static const _serviceLabels = <String>[
    'хизмат',
    'xizmat',
    'услуга',
    'usluga',
    'service',
  ];

  static List<String> categoryLabels(String category) {
    switch (category) {
      case 'service':
        return _serviceLabels;
      case 'product':
      default:
        return _productLabels;
    }
  }

  static List<String> extraFields(TvClip c) {
    return [
      c.description,
      c.districtLabel,
      c.districtId,
      if ((c.mfy ?? '').trim().isNotEmpty) c.mfy!.trim(),
      if (c.hasPrice) '${c.price}',
      tvOwnerGivenName(c.ownerName),
      ...categoryLabels(c.category),
      ...c.searchTokens,
    ];
  }

  static List<String> matchFields(TvClip c) => [c.title, ...extraFields(c)];

  static bool matches(TvClip c, String query) =>
      CatalogSearch.matches(query, matchFields(c));

  static int score(TvClip c, String query) => CatalogSearch.score(
        query,
        title: c.title,
        extra: extraFields(c),
      );

  /// Чоп этишдаги `searchTokens` — икки скрипт + категория + туман + префикс.
  static List<String> buildTokens({
    required String title,
    String description = '',
    String districtLabel = '',
    String category = '',
    String ownerName = '',
    String mfy = '',
  }) {
    final blob = [
      title,
      description,
      districtLabel,
      mfy,
      tvOwnerGivenName(ownerName),
      ...categoryLabels(category),
    ].where((s) => s.trim().isNotEmpty).join(' ');
    final out = <String>{...AdSearchText.buildTokens(title, blob)};
    for (final w in AdSearchText.queryTokens(title)) {
      if (w.length < 4) continue;
      for (var i = 3; i < w.length && out.length < AdSearchText.maxTokens; i++) {
        out.add(w.substring(0, i));
      }
    }
    return out.take(AdSearchText.maxTokens).toList(growable: false);
  }
}
