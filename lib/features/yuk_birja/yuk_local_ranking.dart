import '../../services/geo_math_service.dart';
import 'models/yuk_local_driver.dart';
import 'yuk_vehicle_types.dart';

/// Туман ичида рўйхатни қидирувчи GPS ↔ эълон жойи бўйича саралаш.
class YukLocalRanking {
  YukLocalRanking({GeoMathService? geo}) : _geo = geo ?? const GeoMathService();

  final GeoMathService _geo;

  /// Йўл масофаси (P0): тўғри чизиқ × йўл коэффициенти.
  static const roadFactor = 1.35;

  /// Шаҳар ичида юк машинаси ўртача тезлиги (км/соат) — ETA учун.
  static const avgSpeedKmh = 27.0;

  List<YukLocalDriverRanked> rank({
    required List<YukLocalDriver> drivers,
    required double userLat,
    required double userLng,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final ranked = <YukLocalDriverRanked>[];

    for (final d in drivers) {
      if (!d.hasGps) continue;
      if (d.isExpired(at)) continue;
      if (!d.isWithinWorkHours(at)) continue;

      final straight = _geo.haversineKm(userLat, userLng, d.lat!, d.lng!);
      final road = straight * roadFactor;
      final eta = (road / avgSpeedKmh * 60).ceil().clamp(1, 999);
      ranked.add(
        YukLocalDriverRanked(
          driver: d,
          straightKm: straight,
          roadKm: road,
          etaMinutes: eta,
          inRadius: d.coversDistance(straight),
        ),
      );
    }

    int readiness(YukLocalDriver d) {
      if (d.loadStatus == YukLocalLoadStatus.empty) return 0;
      if (d.loadStatus == YukLocalLoadStatus.busy) return 1;
      return 2;
    }

    ranked.sort((a, b) {
      // 0) Мотоцикл доимий биринчи
      final vp = yukVehicleListPriority(a.driver.vehicleType)
          .compareTo(yukVehicleListPriority(b.driver.vehicleType));
      if (vp != 0) return vp;
      // 1) Тайёрлик
      final r = readiness(a.driver).compareTo(readiness(b.driver));
      if (r != 0) return r;
      // 2) Радиус мослиги
      if (a.inRadius != b.inRadius) return a.inRadius ? -1 : 1;
      // 3) ETA
      final e = a.etaMinutes.compareTo(b.etaMinutes);
      if (e != 0) return e;
      // 4) Масофа
      return a.roadKm.compareTo(b.roadKm);
    });

    return ranked;
  }
}
