class PriceService {
  static double base = 3000;     // базавий нарх
  static double perKm = 2000;    // 1 км учун

  static double calculate({
    required double distanceKm,
  }) {
    return base + (distanceKm * perKm);
  }
}