import '../../models/home_module.dart';

/// Bosh ekran: yuqori 2 katta + pastda service kartalar ketma-ket.
class HomeScreenLayout {
  const HomeScreenLayout({
    this.featuredLeft,
    this.featuredRight,
    this.taxiModules = const [],
    this.extraModules = const [],
  });

  final HomeModule? featuredLeft;
  final HomeModule? featuredRight;
  final List<HomeModule> taxiModules;
  final List<HomeModule> extraModules;

  bool get hasFeaturedRow => featuredLeft != null || featuredRight != null;
}

class HomeGridLayout {
  HomeGridLayout._();

  static const double maxWidth = 520;
  static const double spacing = 12;
  static const double horizontalPadding = 18;

  /// Ticker matn maydoni balandligi (home_ticker_layout bilan bir xil).
  static const double tickerBarHeightScale = 1.2;

  /// Barcha 5 karta — ticker ostidan (asosiy bo‘shliq).
  static const double tickerToCardsGap = 8;

  /// Ticker kengayganda kartalar pastga siljishi uchun qo‘shimcha bo‘shliq.
  static double get cardsGapBelowTicker {
    const refTickerBarHeight = 50.0;
    return tickerToCardsGap +
        refTickerBarHeight * (tickerBarHeightScale - 1.0);
  }

  static const List<String> _featuredIds = ['bread', 'jobs'];
  static const List<String> _taxiIds = [
    'cheap_products_home',
    'marshrut',
    'local_taxi',
    'intercity',
  ];

  static HomeModule? _find(List<HomeModule> catalog, String id) {
    for (final m in catalog) {
      if (m.id == id && m.enabled) return m;
    }
    return null;
  }

  static HomeScreenLayout buildLayout(List<HomeModule> catalog) {
    final placed = <String>{..._featuredIds, ..._taxiIds};
    final extra = catalog
        .where((m) => m.enabled && !placed.contains(m.id))
        .toList(growable: false);

    return HomeScreenLayout(
      featuredLeft: _find(catalog, 'bread'),
      featuredRight: _find(catalog, 'jobs'),
      taxiModules: [
        for (final id in _taxiIds)
          if (_find(catalog, id) != null) _find(catalog, id)!,
      ],
      extraModules: extra,
    );
  }

  /// Yuqori qator (Non + Ish) — balandlik (~15% qisqaroq).
  static double featuredRowHeight(double screenHeight) {
    return (screenHeight * 0.126).clamp(85.0, 108.0);
  }
}
