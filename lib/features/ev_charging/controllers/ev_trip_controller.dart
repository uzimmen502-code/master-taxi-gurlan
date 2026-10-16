import 'package:flutter/foundation.dart';

import '../../../models/ev_charging_station.dart';
import '../../../models/directions_result.dart';
import '../../../models/oil_vehicle.dart';
import '../../../services/google_directions_service.dart';
import '../../../services/polyline_decoder.dart';
import '../models/ev_trip_plan.dart';
import 'ev_trip_planner.dart';

/// «Менинг автомобилларим»даги машинадан режа учун спецификация.
/// Маълумот тўлиқ бўлмаса `null` — UI «автомобилни тўлдиринг» деб
/// йўналтиради, ўйлаб топилган қиймат билан режа тузилмайди.
extension OilVehicleEvSpec on OilVehicle {
  EvCarSpec? get evSpec => hasEvSpec
      ? EvCarSpec(
          usableBatteryKwh: evBatteryKwh,
          consumptionKwhPer100Km: evConsumptionKwhPer100Km,
          connectors: evConnectors,
        )
      : null;
}

/// [EvTripController.replaceStop] natijasi.
enum EvReplaceResult {
  /// Almashtirildi, reja tayyor.
  replaced,

  /// Almashtirildi, lekin yangi stansiyaga yetib bo'lmaydi (uzilish) -
  /// reja `gapTooLarge`; "Қайтариш" bilan qaytarish mumkin.
  infeasible,

  /// Almashtirib bo'lmadi (reja yo'q, noto'g'ri indeks, stansiya koridorda
  /// emas yoki oldingi to'xtashdan orqada) - hech narsa o'zgarmadi.
  unavailable,
}

class _EvTripSnapshot {
  const _EvTripSnapshot({
    required this.plan,
    required this.corridor,
    required this.pinned,
    required this.excluded,
  });

  final EvTripPlan plan;
  final List<EvCorridorStation> corridor;
  final Set<String> pinned;
  final Set<String> excluded;
}

/// ⚡ EV сафар ёрдамчиси — «Қаерга борамиз?» оқимининг ҳолати.
///
/// Вазифаси фақат ЁПИШТИРИШ: маршрут геометрияси (мавжуд
/// `GoogleDirectionsService` — Яндекс эмас, лицензия сабабли) →
/// коридор → [EvTripPlanner.plan]. Ҳисоб мантиғи планерда, бу ерда
/// такрорланмайди.
///
/// Станциялар рўйхати ТАШҚАРИДАН узатилади (`watchAllActive` стримидан) —
/// контроллер ўз обунасини яратмайди, шунинг учун экран билан иккита
/// параллел сўров бўлмайди.
class EvTripController extends ChangeNotifier {
  EvTripController({
    GoogleDirectionsService? directions,
    PolylineDecoder decoder = const PolylineDecoder(),
  })  : _directions = directions ?? GoogleDirectionsService(),
        _decoder = decoder;

  /// Tayyor reja bilan (tarmoq so'rovisiz): xarita ekrani o'z ichida
  /// stansiyani almashtirish va zaryadni yangilash uchun shu kontrollerdan
  /// foydalanadi. Marshrut/koridor qayta so'ralmaydi.
  EvTripController.seeded({
    required EvTripPlan plan,
    required List<EvRoutePoint> route,
    required List<EvCorridorStation> corridor,
    int routeMinutes = 0,
    double? destinationLat,
    double? destinationLng,
  })  : _directions = GoogleDirectionsService(),
        _decoder = const PolylineDecoder() {
    _plan = plan;
    _routePoints = route;
    _corridor = corridor;
    _routeKm = plan.totalKm;
    _routeMinutes = routeMinutes;
    _destinationLat = destinationLat;
    _destinationLng = destinationLng;
  }

  final GoogleDirectionsService _directions;
  final PolylineDecoder _decoder;

  /// Haydovchi o'zi tanlagan (almashtirgan) stansiyalar: keyingi qayta
  /// hisoblarda ham majburiy to'xtash bo'lib qoladi.
  final Set<String> _pinned = <String>{};

  /// Haydovchi rad etgan (almashtirilgan) stansiyalar: qayta hisobda asosiy
  /// qilib tanlanmaydi (koridordan o'chirilmaydi - xaritada ko'rinishda qoladi).
  final Set<String> _excluded = <String>{};

  /// Oxirgi o'zgarishdan oldingi holat ("Қайтариш"). Bir bosqichli.
  _EvTripSnapshot? _undo;

  bool _loading = false;
  String? _error;
  EvTripPlan? _plan;
  List<EvCorridorStation> _corridor = const [];
  List<EvRoutePoint> _routePoints = const [];
  double _routeKm = 0;
  int _routeMinutes = 0;
  double? _destinationLat;
  double? _destinationLng;

  bool get loading => _loading;
  String? get error => _error;
  EvTripPlan? get plan => _plan;

  /// Маршрут бўйидаги БАРЧА станциялар — ҳайдовчини хотиржам қилиш учун
  /// харитада режага кирмаганлари ҳам кўрсатилади.
  List<EvCorridorStation> get corridorStations => _corridor;

  List<EvRoutePoint> get routePoints => _routePoints;

  /// Google бўйича ҲАҚИҚИЙ йўл масофаси (км) — тўғри чизиқ эмас.
  double get routeKm => _routeKm;
  int get routeMinutes => _routeMinutes;

  /// Manzilning HAQIQIY koordinatasi: tayyor koordinata berilgan bo'lsa shu,
  /// matnli manzil bo'lsa - Google topgan tugash nuqtasi (end_location).
  /// Reja yo'q bo'lsa null.
  double? get destinationLat => _destinationLat;
  double? get destinationLng => _destinationLng;
  bool get hasDestination => _destinationLat != null && _destinationLng != null;

  bool get hasPlan => _plan != null;

  /// «Қаерга борамиз?» — асосий чақирув.
  ///
  /// Хато бўлса [error] тўлади ва [plan] `null` қолади: ярим-ёлғон режа
  /// кўрсатилмайди.
  Future<void> planTrip({
    required double originLat,
    required double originLng,
    double? destinationLat,
    double? destinationLng,
    String? destinationText,
    required EvCarSpec car,
    required int socPercent,
    required List<EvChargingStation> stations,
    double corridorKm = EvTripPlanner.defaultCorridorKm,
  }) async {
    _loading = true;
    _error = null;
    _plan = null;
    _pinned.clear();
    _excluded.clear();
    _undo = null;
    _destinationLat = null;
    _destinationLng = null;
    notifyListeners();

    try {
      final text = destinationText?.trim() ?? '';
      final DirectionsResult result;
      if (destinationLat != null && destinationLng != null) {
        result = await _directions.fetchSimpleRoute(
          originLat: originLat,
          originLng: originLng,
          destinationLat: destinationLat,
          destinationLng: destinationLng,
        );
      } else if (text.isNotEmpty) {
        // Tuman/viloyatda koordinata yo'q - manzil Google'ga matn bo'lib
        // beriladi (koordinata o'ylab topilmaydi).
        result = await _directions.fetchSimpleRouteToText(
          originLat: originLat,
          originLng: originLng,
          destinationText: text,
        );
      } else {
        _error = 'route_geometry_missing';
        return;
      }

      final points = _decoder
          .decode(result.polyline)
          .map((p) => EvRoutePoint(p.latitude, p.longitude))
          .toList();

      if (points.length < 2) {
        _error = 'route_geometry_missing';
        _plan = null;
        return;
      }

      _routePoints = points;
      _routeMinutes = result.durationMin;
      // Tugash nuqtasi: tayyor koordinata, yo'qsa Google end_locationi,
      // u ham yo'q bo'lsa marshrut chizig'ining oxirgi nuqtasi.
      _destinationLat = destinationLat ?? result.endLat ?? points.last.lat;
      _destinationLng = destinationLng ?? result.endLng ?? points.last.lng;

      // Overview polyline соддалаштирилган — унинг узунлиги Google'нинг
      // йўл масофасидан бир оз қисқа чиқади. Иккита ўлчов аралашиб
      // «фантом» масофа ҳосил бўлмаслиги учун коридор масофалари
      // ҳақиқий йўл масофасига масштабланади.
      final geometryKm = EvTripPlanner.routeLengthKm(points);
      _routeKm = result.distanceKm > 0 ? result.distanceKm : geometryKm;
      final scale = (geometryKm > 0 && result.distanceKm > 0)
          ? result.distanceKm / geometryKm
          : 1.0;

      final raw = EvTripPlanner.corridor(
        route: points,
        stations: stations,
        corridorKm: corridorKm,
      );
      _corridor = scale == 1.0
          ? raw
          : raw
              .map((c) => EvCorridorStation(
                    station: c.station,
                    alongKm: c.alongKm * scale,
                    offRouteKm: c.offRouteKm,
                  ))
              .toList();

      _plan = EvTripPlanner.plan(
        corridorStations: _corridor,
        totalKm: _routeKm,
        car: car,
        startSocPercent: socPercent,
      );
    } on DirectionsNoRouteException {
      // Google bu manzilga yo'l topmadi (ZERO_RESULTS) - tarmoq xatosi emas.
      _error = 'route_geometry_missing';
      _plan = null;
    } catch (e) {
      _error = 'route_request_failed';
      _plan = null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Заряд кутилгандан тез тушди ёки асосий станция мос келмади —
  /// маршрутни ҚАЙТА сўрамасдан режа янгиланади (тармоқ сўрови йўқ).
  ///
  /// Шу ерда заҳира ўз-ўзидан асосийга айланади: янги [socPercent] билан
  /// етиб бориш мумкин бўлган энг яхши нуқта қайта танланади.
  ///
  /// Haydovchi avval almashtirgan (tanlagan) stansiyalar, hali oldinda
  /// bo'lsa, majburiy to'xtash bo'lib qoladi. Oldingi holat "Қайтариш"
  /// uchun saqlanadi ([undo]).
  void replan({
    required EvCarSpec car,
    required int socPercent,
    required double passedKm,
  }) {
    if (_corridor.isEmpty && _routeKm <= 0) return;
    _rememberForUndo();
    final from = passedKm.clamp(0, _routeKm).toDouble();
    _plan = EvTripPlanner.plan(
      corridorStations: _corridor,
      totalKm: _routeKm,
      car: car,
      startSocPercent: socPercent,
      fromAlongKm: from,
      forcedStopIds: _pinned.toList(),
      excludedStationIds: _excluded,
    );
    notifyListeners();
  }

  /// Asosiy stansiya rad etildi («бу ерга бормайман») — ўша нуқта
  /// коридордан чиқарилади ва режа қайта тузилади.
  void rejectStation({
    required String stationId,
    required EvCarSpec car,
    required int socPercent,
    double passedKm = 0,
  }) {
    _rememberForUndo();
    _corridor = _corridor
        .where((c) => c.station.id != stationId)
        .toList(growable: false);
    _inChange = true;
    try {
      replan(car: car, socPercent: socPercent, passedKm: passedKm);
    } finally {
      _inChange = false;
    }
  }

  /// Rejadagi [stopIndex]-to'xtashni [newStationId] stansiyasiga almashtirish
  /// (haydovchi qarori): oldingi to'xtashlar o'zgarmaydi, qolgan qism yangi
  /// to'xtashdan qayta hisoblanadi. Eski stansiya keyingi hisoblarda asosiy
  /// qilib tanlanmaydi.
  ///
  /// Yangi stansiyaga yetib bo'lmasa reja `gapTooLarge` bo'ladi (xuddi shu
  /// uzilish ogohlantirishi ko'rsatiladi), boshqa stansiya o'ylab topilmaydi;
  /// avvalgi reja [undo] bilan qaytariladi.
  EvReplaceResult replaceStop({
    required int stopIndex,
    required String newStationId,
    required EvCarSpec car,
  }) {
    final current = _plan;
    if (current == null ||
        stopIndex < 0 ||
        stopIndex >= current.stops.length) {
      return EvReplaceResult.unavailable;
    }
    final oldId = current.stops[stopIndex].station.id;
    final next = EvTripPlanner.replaceStop(
      current: current,
      stopIndex: stopIndex,
      replacementId: newStationId,
      corridorStations: _corridor,
      car: car,
      excludedStationIds: _excluded,
      pinnedStationIds: _pinned,
    );
    if (next == null) return EvReplaceResult.unavailable;

    _rememberForUndo();
    _pinned
      ..remove(oldId)
      ..add(newStationId);
    _excluded.add(oldId);
    _excluded.remove(newStationId);
    _plan = next;
    notifyListeners();
    return next.status == EvTripPlanStatus.gapTooLarge
        ? EvReplaceResult.infeasible
        : EvReplaceResult.replaced;
  }

  /// Oxirgi o'zgarish ([replaceStop], [replan], [rejectStation]) qaytarilishi
  /// mumkinmi.
  bool get canUndo => _undo != null;

  /// Oxirgi o'zgarishni qaytarish: reja, koridor va haydovchi tanlovlari
  /// o'zgarishdan oldingi holatga qaytadi.
  bool undo() {
    final snap = _undo;
    if (snap == null) return false;
    _undo = null;
    _plan = snap.plan;
    _corridor = snap.corridor;
    _pinned
      ..clear()
      ..addAll(snap.pinned);
    _excluded
      ..clear()
      ..addAll(snap.excluded);
    notifyListeners();
    return true;
  }

  /// "Қайтариш" imkoniyatini yopish (masalan, haydovchi yangi reja bilan
  /// qoldi).
  void discardUndo() {
    if (_undo == null) return;
    _undo = null;
    notifyListeners();
  }

  /// Faqat BIRINCHI o'zgarishda holat saqlanadi: [rejectStation] ichida
  /// [replan] ikkinchi marta chaqirilsa, oldingi (ichki) holat ustiga
  /// yozilmasin.
  bool _inChange = false;
  void _rememberForUndo() {
    if (_inChange) return;
    final plan = _plan;
    if (plan == null) return;
    _undo = _EvTripSnapshot(
      plan: plan,
      corridor: _corridor,
      pinned: {..._pinned},
      excluded: {..._excluded},
    );
  }

  void clear() {
    _plan = null;
    _pinned.clear();
    _excluded.clear();
    _undo = null;
    _corridor = const [];
    _routePoints = const [];
    _routeKm = 0;
    _routeMinutes = 0;
    _destinationLat = null;
    _destinationLng = null;
    _error = null;
    _loading = false;
    notifyListeners();
  }

  /// Навигаторга юбориладиган тўхташлар — режадаги асосий станциялар.
  List<({double lat, double lng})> get navigationStops =>
      (_plan?.stops ?? const <EvTripStop>[])
          .map((s) => (lat: s.station.latitude, lng: s.station.longitude))
          .toList();
}
