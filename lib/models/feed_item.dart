/// Manba: non, taom yoki bozor (`ads` cheap_product).
enum FeedSource {
  bread,
  food,
  market,
}

/// «Barcha mahsulotlar» lentasi uchun bitta mahsulot qatori.
class FeedItem {
  const FeedItem({
    required this.id,
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.unit,
    required this.source,
  });

  final String id;
  final String name;
  final int price;

  /// HTTP, data URL yoki bo‘sh.
  final String imageUrl;

  /// Masalan «дона», «кг» — bo‘sh bo‘lishi mumkin.
  final String unit;
  final FeedSource source;

  /// Tartiblash va dublikatni oldini olish uchun barqaror kalit.
  String get dedupKey => '${source.name}_$id';
}
