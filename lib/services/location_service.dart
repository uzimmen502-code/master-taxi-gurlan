import 'dart:async';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Oddiy lat/lng + accuracy tuzilmasi — Position'ni butunlay UI'ga olib
/// chiqmаслик учун.
class LocationCoords {
  const LocationCoords({
    required this.lat,
    required this.lng,
    this.accuracy,
    this.fromLastKnown = false,
  });

  final double lat;
  final double lng;

  /// GPS аниқлиги (метрда). `null` бўлса — аниқланмаган.
  final double? accuracy;

  /// `getLastKnownPosition` дан олинган (тез, лекин эски бўлиши мумкин).
  final bool fromLastKnown;

  bool get isLowAccuracy => accuracy != null && accuracy! > 100;
}

/// GPS orqali joriy manzilni o'qish uchun yagona joy.
class LocationService {
  const LocationService();

  /// Joriy GPS: охирги нуқта → medium → high.
  Future<LocationCoords> getCurrentCoords({
    Duration mediumTimeout = const Duration(seconds: 5),
    Duration highTimeout = const Duration(seconds: 10),
  }) async {
    await _ensurePermission();

    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw const LocationException(LocationErrorKind.serviceDisabled);
    }

    final last = await Geolocator.getLastKnownPosition();
    if (last != null && _isValidPosition(last)) {
      return _fromPosition(last, fromLastKnown: true);
    }

    try {
      final medium = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: mediumTimeout,
        ),
      );
      if (_isValidPosition(medium)) {
        return _fromPosition(medium);
      }
    } on TimeoutException {
      // high ga o'tamiz
    } catch (_) {
      // high ga o'tamiz
    }

    try {
      final high = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: highTimeout,
        ),
      );
      if (_isValidPosition(high)) {
        return _fromPosition(high);
      }
    } on TimeoutException {
      throw const LocationException(LocationErrorKind.timeout);
    } catch (_) {
      throw const LocationException(LocationErrorKind.lookupFailed);
    }

    throw const LocationException(LocationErrorKind.lookupFailed);
  }

  /// Ikki nuqta orasidagi masofa (km).
  static double distanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
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

  /// Joriy manzil matni (GPS + reverse geocoding ketma-ket).
  Future<String> getCurrentAddress({
    Duration gpsMediumTimeout = const Duration(seconds: 5),
    Duration gpsHighTimeout = const Duration(seconds: 10),
    Duration geocodeTimeout = const Duration(seconds: 5),
  }) async {
    final coords = await getCurrentCoords(
      mediumTimeout: gpsMediumTimeout,
      highTimeout: gpsHighTimeout,
    );
    final text = await addressFromCoords(
      coords.lat,
      coords.lng,
      timeout: geocodeTimeout,
      fallbackToCoords: true,
    );
    return text ??
        '${coords.lat.toStringAsFixed(4)}, ${coords.lng.toStringAsFixed(4)}';
  }

  /// Reverse geocoding — ko'cha nomi (координата матни эмас).
  ///
  /// [fallbackToCoords] `false` бўлса, муваффақиятсизда `null` (onboarding/profil).
  Future<String?> addressFromCoords(
    double lat,
    double lng, {
    Duration timeout = const Duration(seconds: 5),
    bool fallbackToCoords = false,
  }) async {
    try {
      final marks = await placemarkFromCoordinates(lat, lng).timeout(timeout);
      if (marks.isNotEmpty) {
        final p = marks.first;
        final parts = <String>[
          p.street ?? '',
          p.subLocality ?? '',
          p.locality ?? '',
        ].where((s) => s.trim().isNotEmpty).toList();
        if (parts.isNotEmpty) {
          final joined = parts.join(', ');
          if (!_looksLikeCoordinates(joined)) return joined;
        }
      }
      return fallbackToCoords
          ? '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}'
          : null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return fallbackToCoords
          ? '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}'
          : null;
    }
  }

  /// Матнli manzildan taxminiy GPS (admin kuryer marshruti учун).
  Future<LocationCoords?> coordsFromAddress(String address) async {
    final raw = address.trim();
    if (raw.isEmpty) return null;
    final query = raw.toLowerCase().contains('gurlan') ||
            raw.contains('Гурлан')
        ? raw
        : '$raw, Gurlan, Xorazm, Uzbekistan';
    try {
      final marks = await locationFromAddress(query);
      if (marks.isEmpty) return null;
      final first = marks.first;
      return LocationCoords(lat: first.latitude, lng: first.longitude);
    } catch (_) {
      return null;
    }
  }

  static bool _isValidPosition(Position pos) {
    if (pos.latitude.abs() < 1e-6 && pos.longitude.abs() < 1e-6) {
      return false;
    }
    return pos.latitude >= -90 &&
        pos.latitude <= 90 &&
        pos.longitude >= -180 &&
        pos.longitude <= 180;
  }

  static LocationCoords _fromPosition(
    Position pos, {
    bool fromLastKnown = false,
  }) {
    return LocationCoords(
      lat: pos.latitude,
      lng: pos.longitude,
      accuracy: pos.accuracy,
      fromLastKnown: fromLastKnown,
    );
  }

  static bool _looksLikeCoordinates(String text) {
    final t = text.trim();
    return RegExp(r'^-?\d+\.?\d*\s*,\s*-?\d+\.?\d*$').hasMatch(t);
  }
}

enum LocationErrorKind {
  permissionDenied,
  serviceDisabled,
  timeout,
  lookupFailed,
}

class LocationException implements Exception {
  const LocationException(this.kind);
  final LocationErrorKind kind;

  static String userMessage(LocationErrorKind kind) {
    return switch (kind) {
      LocationErrorKind.permissionDenied =>
        'GPS рухсати йўқ. Илтимос, телефон созламаларидан рухсат беринг.',
      LocationErrorKind.serviceDisabled =>
        'GPS ўчиқ. Телефон созламаларидан «Жойлашув»ни ёқинг.',
      LocationErrorKind.timeout =>
        'GPS жавоб бермади. Очиқ жойга чиқиб қайта уриниб кўринг.',
      LocationErrorKind.lookupFailed =>
        'GPS аниқланмади. Очиқ жойга чиқиб қайта уриниб кўринг.',
    };
  }
}
