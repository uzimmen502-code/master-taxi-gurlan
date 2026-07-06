import '../../../utils/fare_calculator.dart';

/// Mahalliy taksi narx hisobi — [FareCalculator] ustiga yupqa qatlam.
@Deprecated('Use FareCalculator directly')
class PriceService {
  static Future<void> loadPrices() => FareCalculator.loadPrices();

  static double calculate({required double distanceKm}) =>
      FareCalculator.calculate(distanceKm: distanceKm).toDouble();

  static double get base => FareCalculator.baseFare.toDouble();

  static double get perKm => FareCalculator.pricePerKm.toDouble();
}
