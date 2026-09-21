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

  Future<void> init() async {
    try {
      final coords = await _locationService.getCurrentCoords();
      _lat = coords.lat;
      _lng = coords.lng;
      _watchStations();
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
    final lat = _lat;
    final lng = _lng;
    if (lat == null || lng == null) return;
    _stationsSub?.cancel();
    _stationsSub = _repository.watchNearby(lat: lat, lng: lng).listen((list) {
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
