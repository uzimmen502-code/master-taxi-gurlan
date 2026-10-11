import '../../services/geo_math_service.dart';
import 'models/yuk_local_driver.dart';
import 'yuk_accept_radius.dart';
import '../yuk_shared/yuk_vehicle_types.dart';

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

    ranked.sort((a, b) {
      // 0) Мотоцикл доимий биринчи
      final vp = yukVehicleListPriority(a.driver.vehicleType)
          .compareTo(yukVehicleListPriority(b.driver.vehicleType));
      if (vp != 0) return vp;
      // 1) Тайёрлик
      final r = _readiness(a.driver).compareTo(_readiness(b.driver));
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

  /// Қидирувчида GPS йўқ (3а-босқич): танланган ҳудуд эълонлари масофасиз.
  /// Филтр [rank] билан бир хил (GPS, муддат, иш вақти); тартиб — мотоцикл
  /// → тайёрлик → энг янги янгиланган.
  List<YukLocalDriverRanked> listWithoutGps({
    required List<YukLocalDriver> drivers,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final rows = [
      for (final d in drivers)
        if (d.hasGps && !d.isExpired(at) && d.isWithinWorkHours(at))
          YukLocalDriverRanked(
            driver: d,
            straightKm: 0,
            roadKm: 0,
            etaMinutes: 0,
            inRadius: true,
            distanceKnown: false,
          ),
    ];
    int ms(YukLocalDriver d) =>
        (d.updatedAt ?? d.createdAt)?.millisecondsSinceEpoch ?? 0;
    rows.sort((a, b) {
      final vp = yukVehicleListPriority(a.driver.vehicleType)
          .compareTo(yukVehicleListPriority(b.driver.vehicleType));
      if (vp != 0) return vp;
      final r = _readiness(a.driver).compareTo(_readiness(b.driver));
      if (r != 0) return r;
      return ms(b.driver).compareTo(ms(a.driver));
    });
    return rows;
  }

  /// Туман даражаси (D-GEO-6, 3а): шу туман эълонлари + ҳудудсиз эскилари
  /// + қўшни туман ҳайдовчиси, агар унинг қамров радиуси қидирувчига етса
  /// (қўшни туманникини яширмаймиз — курьер D-GEO-3 мантиғи). «Бутун туман»
  /// радиуси ўз тумани учун — қўшни туманга етади дегани эмас. [districtId]
  /// бўш бўлса филтр йўқ.
  static List<YukLocalDriverRanked> keepForDistrict(
    List<YukLocalDriverRanked> rows,
    String districtId,
  ) {
    final id = districtId.trim();
    if (id.isEmpty) return rows;
    bool reachesNeighbour(YukLocalDriverRanked r) =>
        r.distanceKnown &&
        !YukAcceptRadius.isCitywide(r.driver.acceptRadiusKm) &&
        r.straightKm <= r.driver.acceptRadiusKm;
    return rows
        .where((r) =>
            r.driver.hasNoDistrict ||
            r.driver.districtId == id ||
            reachesNeighbour(r))
        .toList();
  }

  static int _readiness(YukLocalDriver d) {
    if (d.loadStatus == YukLocalLoadStatus.empty) return 0;
    if (d.loadStatus == YukLocalLoadStatus.busy) return 1;
    return 2;
  }
}
