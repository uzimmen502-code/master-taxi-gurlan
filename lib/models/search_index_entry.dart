import 'package:cloud_firestore/cloud_firestore.dart';

/// Глобал қидирув индекси (`search_index/{id}`).
class SearchIndexEntry {
  const SearchIndexEntry({
    required this.id,
    required this.type,
    required this.moduleId,
    required this.title,
    this.sourceCollection = '',
    this.sourceId = '',
    this.subtitle = '',
    this.price,
    this.imageUrl = '',
    this.iconKey = '',
    this.keywords = const [],
    this.searchTokens = const [],
    this.from = '',
    this.to = '',
    this.districtId = '',
    this.priorityBoost = 0,
    this.active = true,
  });

  static const typeService = 'service';
  static const typePlatformProduct = 'platform_product';
  static const typeJob = 'job';
  static const typeMarketAd = 'market_ad';
  static const typeIntercityRoute = 'intercity_route';
  static const typeBreadProduct = 'bread_product';
  static const typeFoodProduct = 'food_product';
  static const typeYukListing = 'yuk_listing';
  static const typeLocalPlace = 'local_place';

  final String id;
  final String type;
  final String moduleId;
  final String sourceCollection;
  final String sourceId;
  final String title;
  final String subtitle;
  final int? price;
  final String imageUrl;
  final String iconKey;
  final List<String> keywords;
  final List<String> searchTokens;
  final String from;
  final String to;
  final String districtId;
  final int priorityBoost;
  final bool active;

  static List<String> _strList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  factory SearchIndexEntry.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final geo = d['geo'];
    Map<String, dynamic> g = const {};
    if (geo is Map) {
      g = Map<String, dynamic>.from(geo);
    }
    return SearchIndexEntry(
      id: doc.id,
      type: (d['type'] as String?)?.trim() ?? '',
      moduleId: (d['moduleId'] as String?)?.trim() ?? '',
      sourceCollection: (d['sourceCollection'] as String?)?.trim() ?? '',
      sourceId: (d['sourceId'] as String?)?.trim() ?? '',
      title: (d['title'] as String?)?.trim() ?? '',
      subtitle: (d['subtitle'] as String?)?.trim() ?? '',
      price: (d['price'] as num?)?.toInt(),
      imageUrl: (d['imageUrl'] as String?)?.trim() ?? '',
      iconKey: (d['iconKey'] as String?)?.trim() ?? '',
      keywords: _strList(d['keywords']),
      searchTokens: _strList(d['searchTokens']),
      from: (g['from'] as String?)?.trim() ?? '',
      to: (g['to'] as String?)?.trim() ?? '',
      districtId: (g['districtId'] as String?)?.trim() ?? '',
      priorityBoost: (d['priorityBoost'] as num?)?.toInt() ?? 0,
      active: d['active'] as bool? ?? true,
    );
  }
}
