import 'package:flutter/foundation.dart';

import '../../../services/location_service.dart';

/// Бизнес харитасининг GPS ҳолати (EV харитасидаги `EvChargingMapController` мантиғи билан бир хил):
/// - [init] жойлашувни аниқлайди; GPS ўчиқ/рухсат йўқ бўлса [error]да хабар қолади (харита барибир ишлайди);
/// - [refresh] рухсат СЎРАМАЙДИ ([LocationService.getCoordsIfAllowed]): GPS ёқилганда/рухсат берилганда
///   жойлашувни қайта аниқлаб, хабарни ЎЧИРАДИ. Экран иловага қайтганда ва GPS хизмати ёқилганда чақиради.
class BusinessMapGpsController extends ChangeNotifier {
  BusinessMapGpsController({LocationService locationService = const LocationService()})
      : _location = locationService;

  final LocationService _location;
  bool _disposed = false;

  double? lat;
  double? lng;

  /// «GPS ўчиқ» хабари; `null` — GPS бор (ёки ҳали сўралмаган).
  String? error;

  bool get hasLocation => lat != null && lng != null;

  /// Биринчи аниқлаш. Қайтади: GPS бор-йўқ.
  Future<bool> init() async {
    try {
      final c = await _location.getCurrentCoords();
      if (_disposed) return false;
      lat = c.lat;
      lng = c.lng;
      error = null;
      notifyListeners();
      return true;
    } catch (e) {
      if (_disposed) return false;
      error = LocationException.userMessage(
        e is LocationException ? e.kind : LocationErrorKind.lookupFailed,
      );
      notifyListeners();
      return false;
    }
  }

  /// Хабар кўрсатилган бўлса қайта аниқлайди. Қайтади: хабар ўчдими (GPS топилдими).
  Future<bool> refresh() async {
    if (error == null) return false;
    final c = await _location.getCoordsIfAllowed();
    if (_disposed || c == null) return false;
    lat = c.lat;
    lng = c.lng;
    error = null;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
