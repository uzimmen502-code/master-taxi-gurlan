import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../ads/utils/ad_search_text.dart';
import '../../tv_market/models/tv_shop.dart';

/// «Бозорлар» сервер қидируви (2026-11-16): `tv_shop_items.searchTokens` (фақат сервер ёзади —
/// `functions/market_search_tokens.js`, onShopItemSearchTokens; тўплам: сўзлар + ≥3 ҳарфли бошлар, ≤60,
/// асл/лотин/кирилл). Индекслар: (status, market, searchTokens CONTAINS, createdAt DESC) ва
/// (status, searchTokens CONTAINS, createdAt DESC).
///
/// Эски ҳужжатларда токен бўлмаслиги мумкин (backfill — эга) — шу сабаб экранлар клиент филтрини ҳам
/// сақлайди ва натижаларни бирлаштиради ([mergeMarketSearch]).

/// Бир сервер саҳифаси.
const int kMarketSearchLimit = 40;

/// Шундан қисқа сўров — фақат клиентда.
const int kMarketSearchMinChars = 2;

/// Ёзиш тўхтагандан кейин сервер сўрови.
const Duration kMarketSearchDebounce = Duration(milliseconds: 350);

/// Сервер сўз бошларини 15 ҳарфгача ёзади (`PREFIX_MAX_LEN`); узун сўз шу узунликда қирқилади.
const int kMarketSearchTokenMaxLen = 15;

/// Сервер сўз бошларини ≥3 ҳарфдан ёзади (`PREFIX_MIN_LEN`); 2 ҳарфли токен фақат бутун сўзга мос.
const int kMarketSearchPrefixMinLen = 3;

/// Сўровнинг биринчи сўзидан битта `array-contains` токени ёки `null` (сервер сўрови йўқ).
///
/// [AdSearchText.queryTokens] тартибида биринчи сўз олинади; номзодлар: лотин (белгилар бирлашган,
/// иккала ёзувдаги эълон учун энг барқарор шакл) → асл → кирилл. Сервер `'` билан тугайдиган бошни
/// ЁЗМАЙДИ — бундай номзод ўтказиб юборилади. Қолган сўзлар — клиентда текширилади.
String? marketServerSearchToken(String query) {
  final q = query.trim();
  if (q.length < kMarketSearchMinChars) return null;
  final tokens = AdSearchText.queryTokens(q);
  if (tokens.isEmpty) return null;
  final first = tokens.first;
  final candidates = <String>[
    AdSearchText.toLatin(first),
    first,
    AdSearchText.toCyrillic(first),
  ];
  for (final raw in candidates) {
    final c = raw.length > kMarketSearchTokenMaxLen ? raw.substring(0, kMarketSearchTokenMaxLen) : raw;
    if (c.length < kMarketSearchMinChars) continue;
    // Бутун 2 ҳарфли сўз мос келиши мумкин; ундан узун кесилган/бош токен `'` билан тугамасин.
    if (c.endsWith("'")) continue;
    return c;
  }
  return null;
}

// = AdSearchText._wordSplit (сервер WORD_SPLIT билан бир хил).
final RegExp _wordSplit = RegExp(r"[^0-9a-zA-Zа-яёўқғҳА-ЯЁЎҚҒҲʻʼ']+", unicode: true);

Set<String> _forms(String w) {
  final f = AdSearchText.foldMarks(w);
  return {f, AdSearchText.toLatin(f), AdSearchText.toCyrillic(f)};
}

/// Сервер топган эълон учун қолган сўзлар текшируви (сервер семантикаси: ҳар бир сўров сўзи — сарлавҳа/тавсиф/
/// сотувчи сўзларидан бирининг боши, исталган ёзувда). Клиентнинг қатъий [CatalogSearch] (morph) филтри
/// «telef» → «telefon» каби бош мосликни рад этарди — сервер натижаси шу функция билан текширилади.
bool marketServerItemMatches(TvShopItem i, String query) {
  final words = AdSearchText.foldMarks(query).split(_wordSplit).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return true;
  final hay = <String>{};
  for (final w in '${i.title} ${i.description} ${i.ownerName}'.toLowerCase().split(_wordSplit)) {
    if (w.isNotEmpty) hay.addAll(_forms(w));
  }
  for (final w in words) {
    final forms = _forms(w);
    if (!hay.any((h) => forms.any(h.startsWith))) return false;
  }
  return true;
}

/// Сервер сўрови параметрлари (Firestore'га механик қўлланади — [applyMarketSearch]).
@immutable
class MarketSearchRequest {
  const MarketSearchRequest({required this.token, this.market, this.limit = kMarketSearchLimit});

  /// `searchTokens arrayContains`.
  final String token;

  /// `null` — барча бозорлар (Аралаш).
  final String? market;
  final int limit;

  /// Тенглик филтрлари.
  Map<String, Object> get equals => {
        'status': 'active',
        if (market != null && market!.isNotEmpty) 'market': market!,
      };

  static const String arrayField = 'searchTokens';
  static const String orderField = 'createdAt';
  static const bool orderDescending = true;

  /// Бозор экрани учун; токен чиқмаса — `null`.
  static MarketSearchRequest? forQuery(String query, {String? market, int limit = kMarketSearchLimit}) {
    final t = marketServerSearchToken(query);
    if (t == null) return null;
    return MarketSearchRequest(token: t, market: market, limit: limit);
  }

  @override
  bool operator ==(Object other) =>
      other is MarketSearchRequest && other.token == token && other.market == market && other.limit == limit;

  @override
  int get hashCode => Object.hash(token, market, limit);

  @override
  String toString() => 'MarketSearchRequest(token=$token, market=$market, limit=$limit)';
}

/// Бир сервер саҳифаси: [cursor] — кейинги саҳифа учун (Firestore'да охирги ҳужжат).
class MarketSearchPage {
  const MarketSearchPage(this.items, this.cursor, {required this.hasMore});
  final List<TvShopItem> items;
  final Object? cursor;
  final bool hasMore;

  static const empty = MarketSearchPage(<TvShopItem>[], null, hasMore: false);
}

/// [MarketSearchRequest] → Firestore сўрови.
Query<Map<String, dynamic>> applyMarketSearch(
  Query<Map<String, dynamic>> base,
  MarketSearchRequest r, {
  DocumentSnapshot<Map<String, dynamic>>? startAfter,
}) {
  var q = base;
  for (final e in r.equals.entries) {
    q = q.where(e.key, isEqualTo: e.value);
  }
  q = q
      .where(MarketSearchRequest.arrayField, arrayContains: r.token)
      .orderBy(MarketSearchRequest.orderField, descending: MarketSearchRequest.orderDescending);
  if (startAfter != null) q = q.startAfterDocument(startAfter);
  return q.limit(r.limit);
}

/// Firestore'да бир саҳифа; бузилган ҳужжат ўтказиб юборилади (фақат лог).
Future<MarketSearchPage> fetchMarketSearchPage(
  Query<Map<String, dynamic>> base,
  MarketSearchRequest r, {
  Object? startAfter,
}) async {
  final snap = await applyMarketSearch(
    base,
    r,
    startAfter: startAfter is DocumentSnapshot<Map<String, dynamic>> ? startAfter : null,
  ).get();
  final items = <TvShopItem>[];
  for (final d in snap.docs) {
    try {
      items.add(TvShopItem.fromFirestore(d));
    } catch (e) {
      debugPrint('[MarketSearch] skip ${d.id}: $e');
    }
  }
  return MarketSearchPage(
    items,
    snap.docs.isEmpty ? null : snap.docs.last,
    hasMore: snap.docs.length >= r.limit,
  );
}

/// Индекс йўқ/қурилмоқда (`failed-precondition`) — шу экран сессиясида фақат клиент қидируви.
bool isMarketSearchIndexError(Object e) => e is FirebaseException && e.code == 'failed-precondition';

/// Диагностика коди (25-банд): фойдаланувчига эмас, логга.
String marketSearchErrorCode(Object e) =>
    isMarketSearchIndexError(e) ? 'MARKET_SEARCH_INDEX_MISSING' : 'MARKET_SEARCH_FAILED';

/// Аралаш қидируви (барча бозорлар): `status == active && searchTokens arrayContains` — энг янги [limit] та.
/// Индекс хатосида — аввалги оддий `arrayContains` сўровига ([legacy], автоматик индекс; ҳолат клиентда)
/// қайтади, яъни Аралаш олдинги ҳолатдан ёмонлашмайди. Бошқа хато — юқорига (чақирувчи логлайди).
Future<List<TvShopItem>> searchAllMarkets(
  String query, {
  required Future<MarketSearchPage> Function(MarketSearchRequest request) primary,
  required Future<List<TvShopItem>> Function(String token, int limit) legacy,
  int limit = kMarketSearchLimit,
}) async {
  final req = MarketSearchRequest.forQuery(query, limit: limit);
  if (req == null) return const [];
  try {
    final page = await primary(req);
    return page.items.where((i) => i.isActive).toList(growable: false);
  } catch (e) {
    if (!isMarketSearchIndexError(e)) rethrow;
    debugPrint('[MarketSearch] ${marketSearchErrorCode(e)} scope=all -> legacy: $e');
    final items = await legacy(req.token, limit);
    return items.where((i) => i.isActive).toList(growable: false);
  }
}

/// Клиент (юкланган саҳифалар) ва сервер натижалари: id бўйича такрорсиз, энг янгиси олдин
/// (`createdAt` йўғи — охирида; тенгларда кириш тартиби сақланади — аввал [local]).
List<TvShopItem> mergeMarketSearch(Iterable<TvShopItem> local, Iterable<TvShopItem> server) {
  final byId = <String, TvShopItem>{};
  for (final i in local) {
    byId.putIfAbsent(i.id, () => i);
  }
  for (final i in server) {
    byId.putIfAbsent(i.id, () => i);
  }
  final list = byId.values.toList();
  final order = {for (var k = 0; k < list.length; k++) list[k].id: k};
  list.sort((a, b) {
    final ta = a.createdAt;
    final tb = b.createdAt;
    if (ta != null && tb != null) {
      final c = tb.compareTo(ta);
      if (c != 0) return c;
    } else if (ta != null) {
      return -1;
    } else if (tb != null) {
      return 1;
    }
    return order[a.id]!.compareTo(order[b.id]!);
  });
  return list;
}
