import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/tv_clip.dart';

/// Лентани CDN'даги тайёр JSON'дан ўқийди (Phase 3, клиент ярми).
///
/// НИМА УЧУН. Илгари лента ҳар очилганда Firestore'дан ўқиларди ва
/// сўров қайтарган ҲАР ҲУЖЖАТ учун битта read кетарди (саҳифада 20 та).
/// Мазмун эса барча томошабин учун бир хил. Сервер уни ҳар 5 дақиқада
/// тайёрлаб R2'га қўяди (`functions/tv_feed.js`), клиент эса CDN'дан
/// олади: лента учун Firestore read → 0, кечикиш ~200 мс дан ~50 мс га.
///
/// ЭНГ МУҲИМ ХУСУСИЯТИ — ҚАЙТИШ ЙЎЛИ. Бу манба ИХТИЁРИЙ: JSON ҳали
/// ёзилмаган бўлса, тармоқ йиқилса, формат танилмаса ёки файл эскирган
/// бўлса, метод `null` қайтаради ва чақирувчи одатдагидек Firestore'дан
/// ўқийверади. Шунинг учун буни релиз қилиш хавфсиз: сервер builder'и
/// ишламаса ҳам лента аввалгидек ишлайди.
class TvFeedCdn {
  TvFeedCdn._();

  /// Сервердаги `R2_PUBLIC_BASE` билан бир хил бўлиши шарт
  /// (`functions/tv_clip_output.js`).
  static const String _base = 'https://video.ava-uz.com';

  /// Сервердаги `FEED_VERSION` билан бир хил (`functions/tv_feed.js`).
  static const String _version = 'v1';

  /// Шунча эски JSON ишлатилмайди — builder тўхтаб қолган бўлиши
  /// мумкин, ундан кўра Firestore'дан янгисини олган яхши.
  static const Duration maxAge = Duration(hours: 6);

  /// Тармоқ кутиши — лента очилиши бунга қараб кечикмаслиги керак.
  static const Duration timeout = Duration(seconds: 4);

  /// Тест учун алмаштирилади.
  @visibleForTesting
  static Future<http.Response> Function(Uri url)? getOverride;

  /// Таб → сервердаги ҳовуз номи. Клиентдаги `_categoriesForTab`
  /// қайтарган рўйхатга мос келади.
  static String? tabFor(List<String>? categories) {
    if (categories == null || categories.isEmpty) return 'all';
    final s = {...categories};
    if (s.length == 1 && s.contains('news')) return 'news';
    if (s.containsAll({'product', 'service', 'ad'}) && s.length == 3) {
      return 'market';
    }
    // Нотаниш комбинация — CDN'да бундай ҳовуз йўқ.
    return null;
  }

  static Uri pageUrl(String districtId, String tab, int page) =>
      Uri.parse('$_base/feed/$_version/$districtId/$tab/p$page.json');

  /// Битта саҳифа. Ололмаса — `null` (чақирувчи Firestore'га қайтади).
  static Future<TvFeedCdnPage?> fetchPage({
    required String districtId,
    required List<String>? categories,
    int page = 1,
    DateTime? now,
  }) async {
    if (districtId.isEmpty || page < 1) return null;
    final tab = tabFor(categories);
    if (tab == null) return null;

    try {
      final url = pageUrl(districtId, tab, page);
      final res = await (getOverride?.call(url) ??
          http.get(url).timeout(timeout));
      if (res.statusCode != 200) return null;

      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is! Map<String, dynamic>) return null;
      if (body['v'] != _version) return null;

      final builtAtMs = (body['builtAtMs'] as num?)?.toInt() ?? 0;
      if (builtAtMs <= 0) return null;
      final builtAt = DateTime.fromMillisecondsSinceEpoch(builtAtMs);
      if ((now ?? DateTime.now()).difference(builtAt) > maxAge) return null;

      final raw = body['clips'];
      if (raw is! List) return null;
      final clips = <TvClip>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final id = '${m['id'] ?? ''}';
        if (id.isEmpty) continue;
        try {
          clips.add(TvClip.fromMap(id, m));
        } catch (_) {
          // Битта бузуқ ёзув бутун лентани йиқитмасин.
        }
      }

      final pages = (body['pages'] as num?)?.toInt() ?? 1;
      return TvFeedCdnPage(
        clips: clips,
        page: (body['page'] as num?)?.toInt() ?? page,
        pages: pages,
        builtAt: builtAt,
      );
    } catch (e) {
      debugPrint('[TvFeedCdn] $districtId/$page: $e');
      return null;
    }
  }
}

/// CDN'дан олинган битта саҳифа.
class TvFeedCdnPage {
  const TvFeedCdnPage({
    required this.clips,
    required this.page,
    required this.pages,
    required this.builtAt,
  });

  final List<TvClip> clips;
  final int page;
  final int pages;
  final DateTime builtAt;

  bool get hasMore => page < pages;
}
