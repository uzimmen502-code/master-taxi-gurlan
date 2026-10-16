import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Қурилма GPS'идан битта нуқта (машина). `Position`ни UI'га чиқармаслик
/// учун ўз типимиз ([LocationCoords] нақши).
class EvCarFix {
  const EvCarFix({
    required this.lat,
    required this.lng,
    this.headingDeg,
    this.speedMps,
    this.accuracyM,
  });

  final double lat;
  final double lng;

  /// Қурилма маълум қилган йўналиш (градус, шимолдан соат мили бўйича);
  /// номаълум бўлса `null`.
  final double? headingDeg;

  /// Тезлик (м/с); номаълум бўлса `null`.
  final double? speedMps;
  final double? accuracyM;
}

/// GPS оқими манбаи — тестда сохта берилади.
abstract class EvCarLocationSource {
  /// Рухсат берилмаган ёки GPS ўчиқ бўлса `null` — рухсат қайта СЎРАЛМАЙДИ
  /// (ёки ҳеч қачон сўралмайди: сафар режаси учун GPS аввал берилган).
  Future<Stream<EvCarFix>?> open();
}

/// Ҳақиқий манба: `Geolocator.getPositionStream` (юқори аниқлик, ~10 м
/// филтр — [EvNavigationSessionController] билан бир хил созламалар).
class GeolocatorCarLocationSource implements EvCarLocationSource {
  const GeolocatorCarLocationSource();

  static const LocationSettings settings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10,
  );

  @override
  Future<Stream<EvCarFix>?> open() async {
    final perm = await Geolocator.checkPermission();
    if (perm != LocationPermission.always &&
        perm != LocationPermission.whileInUse) {
      return null;
    }
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    return _stream();
  }

  Stream<EvCarFix> _stream() async* {
    // Биринчи ҳаракатни кутмасдан маркер чиқиши учун — охирги маълум нуқта.
    final last = await Geolocator.getLastKnownPosition();
    if (last != null && _valid(last)) yield _fix(last);
    yield* Geolocator.getPositionStream(locationSettings: settings)
        .where(_valid)
        .map(_fix);
  }

  static bool _valid(Position p) =>
      !(p.latitude.abs() < 1e-6 && p.longitude.abs() < 1e-6);

  static EvCarFix _fix(Position p) => EvCarFix(
        lat: p.latitude,
        lng: p.longitude,
        headingDeg: p.heading,
        speedMps: p.speed,
        accuracyM: p.accuracy,
      );
}

/// ⚡ Машинанинг жонли ҳолати (сафар харитаси учун).
///
/// - GPS рухсати йўқ / GPS ўчиқ / оқим хатоси: [fix] `null` қолади, ҳеч
///   қандай хато ташланмайди, рухсат сўралмайди, қайта уриниш цикли йўқ;
/// - иловa фонга ўтса [pause] (оқим ёпилади), қайтса [resume];
/// - йўналиш: қурилма йўналиши ҳаракатда ишончли, тўхтаганда эмас —
///   [resolveHeading] қоидаси бўйича.
class EvCarTracker extends ChangeNotifier {
  EvCarTracker(
      {EvCarLocationSource source = const GeolocatorCarLocationSource()})
      : _source = source;

  final EvCarLocationSource _source;
  StreamSubscription<EvCarFix>? _sub;
  bool _opened = false;
  bool _disposed = false;
  bool _unavailable = false;

  EvCarFix? _fix;
  double _heading = 0;

  /// Охирги нуқта; ҳали йўқ ёки GPS мавжуд эмас — `null` (маркер чизилмайди).
  EvCarFix? get fix => _fix;
  bool get hasFix => _fix != null;

  /// Маркерни буриш бурчаги (градус).
  double get heading => _heading;

  /// GPS рухсати йўқ/ўчиқ ёки оқим хато берган.
  bool get unavailable => _unavailable;

  Future<void> start() async {
    if (_opened || _disposed) return;
    _opened = true;
    await _subscribe();
  }

  Future<void> _subscribe() async {
    await _sub?.cancel();
    _sub = null;
    try {
      final stream = await _source.open();
      if (_disposed) return;
      if (stream == null) {
        _unavailable = true;
        notifyListeners();
        return;
      }
      _unavailable = false;
      _sub = stream.listen(
        _onFix,
        onError: (Object e) {
          // Хато — маркерсиз давом этамиз; қайта уриниш цикли йўқ.
          debugPrint('EvCarTracker: $e');
          _unavailable = true;
          _sub?.cancel();
          _sub = null;
          if (!_disposed) notifyListeners();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('EvCarTracker.open: $e');
      _unavailable = true;
      if (!_disposed) notifyListeners();
    }
  }

  void _onFix(EvCarFix next) {
    if (_disposed) return;
    final prev = _fix;
    _heading = resolveHeading(
      prevLat: prev?.lat,
      prevLng: prev?.lng,
      prevHeading: _heading,
      next: next,
    );
    _fix = next;
    notifyListeners();
  }

  /// Иловa фонга ўтганда — GPS оқимини ёпиш (батарея).
  void pause() {
    _sub?.cancel();
    _sub = null;
  }

  /// Иловa қайтганда — оқимни қайта очиш (рухсат сўралмайди).
  Future<void> resume() async {
    if (!_opened || _disposed || _sub != null) return;
    await _subscribe();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }

  // ---- Тоза ҳисоблар ----

  /// Ҳаракатда (≥ [movingSpeedMps]) қурилма йўналиши; тўхтаганда ё унинг
  /// йўналиши йўқ бўлса — олдинги нуқтадан [minMoveMeters] дан кўп силжиган
  /// бўлса икки нуқта орасидаги азимут; акс ҳолда олдинги йўналиш.
  static double resolveHeading({
    required double? prevLat,
    required double? prevLng,
    required double prevHeading,
    required EvCarFix next,
  }) {
    final reported = next.headingDeg;
    final speed = next.speedMps ?? 0;
    final reportedOk = reported != null &&
        reported.isFinite &&
        reported >= 0 &&
        reported <= 360;
    if (reportedOk && speed >= movingSpeedMps) {
      return reported % 360;
    }
    if (prevLat != null && prevLng != null) {
      final movedM = Geolocator.distanceBetween(
        prevLat,
        prevLng,
        next.lat,
        next.lng,
      );
      if (movedM >= minMoveMeters) {
        return bearingDegrees(prevLat, prevLng, next.lat, next.lng);
      }
    }
    return prevHeading;
  }

  static const double movingSpeedMps = 1.0;
  static const double minMoveMeters = 8;

  /// Бошланғич азимут (градус, 0 = шимол, соат мили бўйича), 0..360.
  static double bearingDegrees(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    double rad(double d) => d * math.pi / 180;
    final p1 = rad(lat1);
    final p2 = rad(lat2);
    final dl = rad(lng2 - lng1);
    final y = math.sin(dl) * math.cos(p2);
    final x = math.cos(p1) * math.sin(p2) -
        math.sin(p1) * math.cos(p2) * math.cos(dl);
    final deg = math.atan2(y, x) * 180 / math.pi;
    return (deg + 360) % 360;
  }
}
