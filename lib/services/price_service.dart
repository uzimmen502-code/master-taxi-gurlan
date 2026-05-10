class PriceService {

  /// Асосий формула (Variant A)
  static double calculate({
    required double baseFare,
    required double distanceKm,
    required double perKm,
  }) {
    return baseFare + (distanceKm * perKm);
  }

  /// Эрта тушиш (ҳозир бир хил формула)
  static double calculateEarlyDrop({
    required double baseFare,
    required double distanceKm,
    required double perKm,
  }) {
    return baseFare + (distanceKm * perKm);
  }

  /// Кейинги босқич учун тайёр (ҳозир ишлатмаймиз)
  static double calculateAdvanced({
    required double baseFare,
    required double distanceKm,
    required double perKm,
    double demandMultiplier = 1.0,
    double nightMultiplier = 1.0,
    double discount = 0.0,
  }) {
    double price = baseFare + (distanceKm * perKm);

    price *= demandMultiplier;
    price *= nightMultiplier;
    price -= discount;

    if (price < baseFare) {
      price = baseFare;
    }

    return price;
  }
}