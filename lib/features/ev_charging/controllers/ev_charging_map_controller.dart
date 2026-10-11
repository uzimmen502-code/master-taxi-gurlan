import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/ev_charging_station.dart';
import '../../../repositories/ev_station_repository.dart';
import '../../../services/location_service.dart';

/// ⚡ Xarita ekrani holati — atrofdagi stansiyalar, GPS, ixtiyoriy filtr.
class EvChargingMapController extends ChangeNotifier {
  EvChargingMapController({
    required EvStationRepository repository,
    required LocationService locationService,
  })  : _repository = repository,
        _locationService = locationService;

  final EvStationRepository _repository;
  final LocationService _locationService;

  StreamSubscription<List<EvChargingStation>>? _stationsSub;

  double? _lat;
  double? _lng;
  List<EvChargingStation> _stations = const [];

  /// Ixtiyoriy filtr — `AC`/`DC`/`AC+DC` (bo'sh — hammasi).
  String? chargingTypeFilter;

  bool loading = true;
  String? error;

  double? get lat => _lat;
  double? get lng => _lng;
  bool get hasLocation => _lat != null && _lng != null;

  List<EvChargingStation> get stations {
    final filter = chargingTypeFilter;
    if (filter == null || filter.isEmpty) return _stations;
    return _stations.where((s) => s.chargingTypes.contains(filter)).toList();
  }

  /// Филтрланмаган тўлиқ рўйхат — сафар режаси учун.
  /// AC/DC филтри фақат харита кўриниши учун; режа эса машинанинг ўз
  /// разъёмига қараб танлайди, шунинг учун унга ҳамма нуқта керак.
  List<EvChargingStation> get allStations => _stations;

  /// GPS йўқ бўлганда харита маркази — Ўзбекистон ўртаси (бутун мамлакат
  /// кўринади, [fallbackZoom]).
  static const fallbackLat = 41.3;
  static const fallbackLng = 64.6;
  static const fallbackZoom = 5.6;

  /// Харита учун марказ: GPS бўлса — у, бўлмаса — мамлакат ўртаси.
  double get centerLat => _lat ?? fallbackLat;
  double get centerLng => _lng ?? fallbackLng;

  Future<void> init() async {
    // Станциялар GPS'га боғлиқ эмас: аввал GPS хатосида `_watchStations`
    // чақирилмас ва экранда фақат хато матни қоларди (geo аудит, 0-босқич).
    _watchStations();
    try {
      final coords = await _locationService.getCurrentCoords();
      _lat = coords.lat;
      _lng = coords.lng;
    } catch (e) {
      error = LocationException.userMessage(
        e is LocationException ? e.kind : LocationErrorKind.lookupFailed,
      );
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _watchStations() {
    // Барча актив нуқталар — 20 км радиус билан чекланмайди (эга қарори,
    // 2026-09-22), фойдаланувчи харитани суриб/кичиклаштириб 456 та импорт
    // қилинган нуқтани ҳам кўра олади. Клубер [EvMapView]да.
    _stationsSub?.cancel();
    _stationsSub = _repository.watchAllActive().listen((list) {
      _stations = list;
      notifyListeners();
    });
  }

  void setChargingTypeFilter(String? type) {
    chargingTypeFilter = type;
    notifyListeners();
  }

  /// Manzil bo'yicha markaz o'zgartirish ("qidiruv", 11-band).
  Future<void> centerOnAddress(String address) async {
    final coords = await _locationService.coordsFromAddress(
      address,
      regionBias: 'uzbekistan',
    );
    if (coords == null) return;
    _lat = coords.lat;
    _lng = coords.lng;
    _watchStations();
    notifyListeners();
  }

  void recenterOnGps(double lat, double lng) {
    _lat = lat;
    _lng = lng;
    _watchStations();
    notifyListeners();
  }

  @override
  void dispose() {
    _stationsSub?.cancel();
    super.dispose();
  }
}
