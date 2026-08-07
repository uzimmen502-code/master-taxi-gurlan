import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/global_search.dart';
import '../models/search_index_entry.dart';

/// `search_index` — глобал қидирув индекси.
///
/// P0: `active==true` cache (client score).
/// P2: биринчи токен бўйича `array-contains` + cache merge (индекс ўсса ҳам топилади).
class SearchIndexRepository {
  SearchIndexRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const cacheLimit = 1500;
  static const tokenQueryLimit = 200;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('search_index');

  List<SearchIndexEntry>? _cache;
  DateTime? _cacheAt;

  Future<List<SearchIndexEntry>> fetchActiveCached({
    Duration ttl = const Duration(minutes: 5),
  }) async {
    final now = DateTime.now();
    if (_cache != null &&
        _cacheAt != null &&
        now.difference(_cacheAt!) < ttl) {
      return _cache!;
    }
    final snap = await _col
        .where('active', isEqualTo: true)
        .limit(cacheLimit)
        .get();
    _cache = snap.docs
        .map(SearchIndexEntry.fromFirestore)
        .toList(growable: false);
    _cacheAt = now;
    return _cache!;
  }

  void invalidateCache() {
    _cache = null;
    _cacheAt = null;
  }

  Future<List<SearchIndexEntry>> search(String query, {int limit = 40}) async {
    final cached = await fetchActiveCached();
    final tokens = GlobalSearch.queryTokens(query);
    var pool = List<SearchIndexEntry>.from(cached);

    // P2: server-side token hit — cache лимитидан ташқари ҳам топади.
    if (tokens.isNotEmpty) {
      final first = tokens.first;
      try {
        final snap = await _col
            .where('active', isEqualTo: true)
            .where('searchTokens', arrayContains: first)
            .limit(tokenQueryLimit)
            .get();
        if (snap.docs.isNotEmpty) {
          final byId = <String, SearchIndexEntry>{
            for (final e in pool) e.id: e,
          };
          for (final doc in snap.docs) {
            byId[doc.id] = SearchIndexEntry.fromFirestore(doc);
          }
          pool = byId.values.toList(growable: false);
        }
      } catch (_) {
        // Индекс ҳали тайёр эмас ёки offline — фақат cache.
      }
    }

    return GlobalSearch.rank(pool, query, limit: limit);
  }
}
