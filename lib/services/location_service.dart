import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Oddiy lat/lng + accuracy tuzilmasi — Position'ni butunlay UI'ga olib
/// chiqмаслик учун.
class LocationCoords {
  const LocationCoords({
    required this.lat,
    required this.lng,
    this.accuracy,
  });

  final double lat;
  final double lng;

  /// GPS аниқлиги (метрда). `null` бўлса — аниқланмаган.
  /// Курьер ва харита учун муҳим: <20m юқори, 20–100m ўрта, >100m паст.
  final double? accuracy;
}

/// GPS orqali joriy manzilni o'qish uchun yagona joy.
///
/// Profil va onboarding ekranlarida bir xil logika takrorlanardi —
/// endi shu yerga ko'chirildi.
class LocationService {
  const LocationService();

  /// Joriy GPS koordinatasi. Xatolik — [LocationException] otadi.
  Future<LocationCoords> getCurrentCoords({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await _ensurePermission();
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: timeout,
      );
      return LocationCoords(
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
      );
    } catch (_) {
      throw const LocationException(LocationErrorKind.lookupFailed);
    }
  }

  /// Ikki nuqta orasidagi masofa (km).
  static double distanceKm(
      double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2) / 1000;
  }

  Future<void> _ensurePermission() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      throw const LocationException(LocationErrorKind.permissionDenied);
    }
  }

  /// Joriy manzilni qaytaradi (street, subLocality, locality).
  /// Hech narsa topilmasa — koordinatalarni matn sifatida.
  ///
  /// Xatolik holatlari uchun [LocationException] otadi.
  Future<String> getCurrentAddress({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final coords = await getCurrentCoords(timeout: timeout);
    return addressFromCoords(coords.lat, coords.lng);
  }

  /// Allaqachon mavjud koordinatalardan manzil matnini olish.
  /// `getCurrentCoords()` чақириб қўйилган ҳолатда, GPSни **қайта ўқимайди**
  /// — reverse geocoding'ни тўғридан-тўғри ишлатaди.
  ///
  /// Hech narsa topilmasa — koordinatalarni matn sifatida qaytaradi.
  Future<String> addressFromCoords(double lat, double lng) async {
    try {
      final marks = await placemarkFromCoordinates(lat, lng);
      if (marks.isNotEmpty) {
        final p = marks.first;
        final parts = <String>[
          p.street ?? '',
          p.subLocality ?? '',
          p.locality ?? '',
        ].where((s) => s.isNotEmpty).toList();
        if (parts.isNotEmpty) return parts.join(', ');
      }
      return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
    } catch (_) {
      // Reverse geocoding ишламаса — координаталар матни.
      return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
    }
  }
}

enum LocationErrorKind {
  permissionDenied,
  lookupFailed,
}

class LocationException implements Exception {
  const LocationException(this.kind);
  final LocationErrorKind kind;
}
