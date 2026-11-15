import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../domain/market_taxonomy.dart';

/// `taxonomy/markets` — сеансда БИР МАРТА ўқилади (listener йўқ, 37-банд: ҳар экран очилишида ўқиш эмас).
/// Хатода кешланмайди — кейинги чақириқ яна уринади. Параллел чақириқлар битта ўқишни кутади.
class MarketTaxonomyRepository {
  MarketTaxonomyRepository._();

  static MarketTaxonomy? _cache;
  static Future<MarketTaxonomy>? _inflight;

  /// Тест учун: ҳужжат ўқувчи (бўлмаса Firestore).
  @visibleForTesting
  static Future<Map<String, dynamic>?> Function()? loaderOverride;

  static MarketTaxonomy? get cached => _cache;

  static Future<MarketTaxonomy> load() {
    final c = _cache;
    if (c != null) return Future.value(c);
    return _inflight ??= _read().then((t) {
      _cache = t;
      return t;
    }).whenComplete(() => _inflight = null);
  }

  static Future<MarketTaxonomy> _read() async {
    final loader = loaderOverride;
    final Map<String, dynamic>? raw;
    if (loader != null) {
      raw = await loader();
    } else {
      final snap = await FirebaseFirestore.instance.collection('taxonomy').doc('markets').get();
      raw = snap.data();
    }
    final t = MarketTaxonomy.fromMap(raw);
    debugPrint('[MarketTaxonomy] loaded version=${t.version} markets=${t.markets.length}');
    return t;
  }

  @visibleForTesting
  static void setForTest(MarketTaxonomy? t) {
    _cache = t;
    _inflight = null;
  }
}
