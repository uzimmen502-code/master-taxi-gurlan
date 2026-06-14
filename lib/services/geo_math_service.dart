import 'dart:math' as math;

class GeoMathService {
  const GeoMathService();

  static const earthRadiusKm = 6371.0;

  bool isValidCoordinate(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat.abs() < 0.000001 && lng.abs() < 0.000001) return false;
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  double haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.pow(math.sin(dLng / 2), 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double bearingDegrees(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final phi1 = _degToRad(lat1);
    final phi2 = _degToRad(lat2);
    final dLng = _degToRad(lng2 - lng1);
    final y = math.sin(dLng) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(dLng);
    return (_radToDeg(math.atan2(y, x)) + 360) % 360;
  }

  double angleDiff(double a, double b) {
    final diff = (a - b).abs() % 360;
    return diff > 180 ? 360 - diff : diff;
  }

  String directionLabel(double degrees) {
    const labels = [
      'Шимол',
      'Шимол-шарқ',
      'Шарқ',
      'Жануб-шарқ',
      'Жануб',
      'Жануб-ғарб',
      'Ғарб',
      'Шимол-ғарб',
    ];
    final idx = ((degrees + 22.5) / 45).floor() % labels.length;
    return labels[idx];
  }

  double _degToRad(double deg) => deg * math.pi / 180;
  double _radToDeg(double rad) => rad * 180 / math.pi;
}
