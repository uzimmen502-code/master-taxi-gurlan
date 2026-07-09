/// Mahalliy taksi mintaqaviy narxi — GPS dan `settings/prices.regions` kaliti.
abstract final class TaxiPriceRegion {
  static const defaultKey = 'default';

  /// Aniqroq mintaqa birinchi (tashkent ichki shahar).
  static String resolveKey({required double lat, required double lng}) {
    if (lat >= 41.10 && lat <= 41.55 && lng >= 69.00 && lng <= 69.55) {
      return 'tashkent';
    }
    if (lat >= 41.20 && lat <= 42.10 && lng >= 60.00 && lng <= 61.10) {
      return 'xorazm';
    }
    if (lat >= 39.50 && lat <= 40.00 && lng >= 66.80 && lng <= 67.20) {
      return 'samarqand';
    }
    if (lat >= 40.90 && lat <= 41.20 && lng >= 71.50 && lng <= 72.00) {
      return 'namangan';
    }
    return defaultKey;
  }
}
