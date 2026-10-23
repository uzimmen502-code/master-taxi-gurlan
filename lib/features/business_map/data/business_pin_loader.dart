import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../models/ev_charging_station.dart';
import '../../restaurants/domain/restaurant_models.dart';
import '../../wholesale/models/wholesale_seller.dart';
import '../domain/business_pin.dart';
import '../domain/viewport_cells.dart';
import 'business_repository.dart';

/// Камера ҳудуди (градус).
class MapBounds {
  const MapBounds({required this.south, required this.west, required this.north, required this.east});

  final double south;
  final double west;
  final double north;
  final double east;

  bool contains(double lat, double lng) => lat >= south && lat <= north && lng >= west && lng <= east;

  double get centerLat => (south + north) / 2;
  double get centerLng => (west + east) / 2;
}

class PinLoadResult {
  const PinLoadResult({required this.pins, this.failed = const {}, this.tooWide = false});

  final List<BusinessPin> pins;

  /// Ўқиб бўлмаган манбалар (масалан, EV — логин/рухсат). Бошқа манбалар барибир кўринади.
  final Set<BusinessSource> failed;

  /// Камера жуда катта ҳудудни қоплайди — ўқиш бажарилмади («яқинлаштиринг»).
  final bool tooWide;
}

/// Харита учун 4 манбани бирлаштириб ўқийди (B-2/B-3). Манба коллекциялари КЎЧИРИЛМАЙДИ: ҳар бири ўз
/// жойида қолади, шу ерда фақат ўқилади (7-банд). Кластерлаш йўқ (B-4): зичлик ҳудуд (≤ 30 катак) ва
/// [maxPins] билан чекланади.
class BusinessPinLoader {
  BusinessPinLoader({FirebaseFirestore? firestore, BusinessRepository? businesses})
      : _firestore = firestore,
        _businesses = businesses;

  final FirebaseFirestore? _firestore;
  final BusinessRepository? _businesses;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  BusinessRepository get _biz => _businesses ?? BusinessRepository();

  /// Ҳар сўровда харитага чиқадиган энг кўп нуқта.
  static const int maxPins = 400;
  static const int _perCellLimit = 50;
  static const int _wholesaleLimit = 300;

  Future<PinLoadResult> load(MapBounds bounds) async {
    final cells = ViewportCells.forBounds(
      south: bounds.south,
      west: bounds.west,
      north: bounds.north,
      east: bounds.east,
    );
    if (cells == null) return const PinLoadResult(pins: [], tooWide: true);

    final failed = <BusinessSource>{};
    Future<List<BusinessPin>> guarded(BusinessSource s, Future<List<BusinessPin>> Function() run) async {
      try {
        return await run();
      } catch (e) {
        debugPrint('[BusinessPinLoader] $s: $e');
        failed.add(s);
        return const [];
      }
    }

    final parts = await Future.wait([
      guarded(BusinessSource.business, () async {
        final rows = await _biz.fetchInCells(cells, limit: maxPins);
        return [for (final b in rows) BusinessPin.fromBusiness(b)];
      }),
      guarded(BusinessSource.restaurant, () => _restaurants(cells)),
      guarded(BusinessSource.evStation, () => _evStations(cells)),
      guarded(BusinessSource.wholesaleSeller, _wholesaleSellers),
    ]);

    final inView = <BusinessPin>[
      for (final list in parts)
        for (final p in list)
          if (bounds.contains(p.lat, p.lng)) p,
    ];
    return PinLoadResult(pins: capNearest(inView, bounds.centerLat, bounds.centerLng), failed: failed);
  }

  /// [maxPins] дан кўп бўлса — марказга энг яқинлари (аниқ ва детерминистик).
  @visibleForTesting
  static List<BusinessPin> capNearest(List<BusinessPin> pins, double lat, double lng, {int cap = maxPins}) {
    if (pins.length <= cap) return pins;
    double d2(BusinessPin p) => (p.lat - lat) * (p.lat - lat) + (p.lng - lng) * (p.lng - lng);
    final sorted = [...pins]..sort((a, b) => d2(a).compareTo(d2(b)));
    return sorted.sublist(0, cap);
  }

  Future<List<BusinessPin>> _restaurants(List<String> cells) async {
    // Индекс: (status, geohash) — `RestaurantsRepository.watchNearby` билан бир хил сўров шакли.
    final snaps = await Future.wait([
      for (final h in cells)
        _db
            .collection('restaurants')
            .where('status', isEqualTo: 'approved')
            .orderBy('geohash')
            .startAt([h])
            .endAt(['$h~'])
            .limit(_perCellLimit)
            .get(),
    ]);
    final out = <BusinessPin>[];
    final seen = <String>{};
    for (final s in snaps) {
      for (final d in s.docs) {
        if (!seen.add(d.id)) continue;
        final pin = BusinessPin.fromRestaurant(Restaurant.fromDoc(d));
        if (pin != null) out.add(pin);
      }
    }
    return out;
  }

  Future<List<BusinessPin>> _evStations(List<String> cells) async {
    final snap = await _db
        .collection('ev_charging_stations')
        .where('isActive', isEqualTo: true)
        .where('geohash4', whereIn: cells)
        .limit(maxPins)
        .get();
    return [
      for (final d in snap.docs)
        if (BusinessPin.fromEvStation(EvChargingStation.fromDoc(d)) case final p?) p,
    ];
  }

  Future<List<BusinessPin>> _wholesaleSellers() async {
    // Сотувчиларда geohash йўқ (≤ 300 та, тасдиқланган); ҳудуд фильтри `load` да.
    final snap = await _db
        .collection('wholesale_sellers')
        .where('approvalStatus', isEqualTo: WholesaleSeller.statusApproved)
        .limit(_wholesaleLimit)
        .get();
    return [
      for (final d in snap.docs)
        if (BusinessPin.fromWholesaleSeller(WholesaleSeller.fromFirestore(d)) case final p?) p,
    ];
  }
}
