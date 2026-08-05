import '../repositories/platform_products_repository.dart';

/// Bosh ekran «Улгуржи нарҳларда тавсия этамиз» bo‘limi uchun mahsulot.
class FeaturedProduct {
  const FeaturedProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.imageUrl,
  });

  final String id;
  final String name;
  final int price;

  /// HTTP, data URL yoki bo‘sh.
  final String imageUrl;
}

/// Platforma do'konidan (`platform_products`) 3 qatorlik (6 ta) tavsiya —
/// bosilganda har doim Платформа дўкони ochiladi, shu mahsulot birinchi
/// o'rinda ko'rinadi.
class FeaturedProductsService {
  FeaturedProductsService({PlatformProductsRepository? platformRepo})
      : _platformRepo = platformRepo ?? PlatformProductsRepository();

  final PlatformProductsRepository _platformRepo;

  static const int rowsCount = 3;
  static const int columnsCount = 2;
  static const int take = rowsCount * columnsCount;

  Future<List<FeaturedProduct>> getFeaturedProducts() async {
    try {
      final products = await _platformRepo.fetchForHomeFeatured(take: take);
      return products
          .map(
            (p) => FeaturedProduct(
              id: p.id,
              name: p.name,
              price: p.price,
              imageUrl: p.coverImageUrl,
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
