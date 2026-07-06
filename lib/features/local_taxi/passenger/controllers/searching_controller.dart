import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../models/active_trip.dart';
import '../../../../models/nearby_driver.dart';
import '../../../../repositories/driver_repository.dart';
import '../../../../repositories/rides_repository.dart';
import '../../../../services/location_service.dart';
import '../../../../utils/fare_calculator.dart';

/// Yo'lovchining "haydovchi qidirish" oqimini boshqaradi (BROADCAST modeli).
///
/// Yo'lovchi haydovchini QO'LDA tanlamaydi. `trips/{id}` `searching` holatida
/// yaratiladi va radius bo'yicha kengayadi (3 km → 5 km → 7 km, har biri 30s);
/// radius `trips.radiusKm` ga yoziladi — atrofdagi BARCHA haydovchilar shu
/// radius ichida so'rovni ko'radi (`watchPendingTrips` + radius gate).
/// Birinchi "Qabul" bosgan haydovchi tripni band qiladi (`reserved`, 10s),
/// so'ng yakuniy qabul qilsa `accepted` bo'ladi (first-accept-wins).
/// Hech kim qabul qilmasa — bo'sh ekran + cancel.
class SearchingController extends ChangeNotifier {
  SearchingController({
    required RidesRepository ridesRepo,
    required DriverRepository driverRepo,
    required LocationService locationService,
    required this.from,
    required this.to,
    required this.taxiType,
    this.existingTripId,
  })  : _ridesRepo = ridesRepo,
        _driverRepo = driverRepo,
        _locationService = locationService;

  /// Mavjud qidiruv tripini tiklash (yangi trip yaratilmaydi).
  final String? existingTripId;

  final RidesRepository _ridesRepo;
  final DriverRepository _driverRepo;
  final LocationService _locationService;

  final String from;
  final String to;
  final String taxiType;

  // ── State ──────────────────────────────────────────────────────────
  String? tripId;
  String _userPhone = '';
  String _userName = '';
  String _userGender = '';
  String _userBirthDate = '';
  double _fromLat = 0;
  double _fromLng = 0;

  /// 0 → 3km, 1 → 5km, 2 → 7km
  int cycle = 0;
  int seconds = 30;

  bool isSearching = true;
  bool _isDisposed = false;
  bool _isCancelled = false;

  List<NearbyDriver> drivers = const [];

  /// Haydovchi qabul qilganda to'ladi. UI buni "iste'mol" qilib dialog ko'rsatadi.
  ActiveTrip? acceptedTrip;

  /// Бирор ҳайдовчи трипни банд қилди (reserved) — "топилди, кутилмоқда".
  /// Шу ҳолатда радиус сикли музлатилади (ҳайдовчи 10с қарор қилмагунча
  /// қидирув кенгаймайди ва тугатилмайди).
  bool driverReserved = false;

  String? errorMessage;

  Timer? _timer;
  StreamSubscription<ActiveTrip>? _tripSub;

  // ── Boshlash ──────────────────────────────────────────────────────
  Future<void> start() async {
    await FareCalculator.loadPrices();

    final prefs = await SharedPreferences.getInstance();
    _userPhone = prefs.getString('user_phone') ?? '';
    _userName = prefs.getString('user_name') ?? '';
    _userGender = prefs.getString('user_gender') ?? '';
    _userBirthDate = prefs.getString('user_birth_date') ?? '';

    try {
      final resumeId = existingTripId?.trim() ?? '';
      if (resumeId.isNotEmpty) {
        tripId = resumeId;
        final existing = await _ridesRepo.getTrip(resumeId);
        if (existing != null) {
          _fromLat = existing.fromLat;
          _fromLng = existing.fromLng;
          if (existing.isReserved) {
            driverReserved = true;
          }
        }
      }

      if (_fromLat == 0 && _fromLng == 0) {
        try {
          final coords = await _locationService.getCurrentCoords();
          _fromLat = coords.lat;
          _fromLng = coords.lng;
        } on LocationException catch (e) {
          errorMessage = switch (e.kind) {
            LocationErrorKind.permissionDenied => 'gps_permission_denied_msg',
            LocationErrorKind.serviceDisabled => 'gps_service_disabled_msg',
            LocationErrorKind.timeout => 'gps_timeout_msg',
            LocationErrorKind.lookupFailed => 'local_gps_required_for_search',
          };
          isSearching = false;
          notifyListeners();
          return;
        }
      }

      if (resumeId.isEmpty) {
        tripId = await _ridesRepo.createSearchRequest(
          userPhone: _userPhone,
          userName: _userName,
          userGender: _userGender,
          userBirthDate: _userBirthDate,
          fromAddr: from,
          toAddr: to,
          fromLat: _fromLat,
          fromLng: _fromLng,
          taxiType: taxiType,
          initialRadiusKm: _radiusForCycle(0),
        );
      }
      _tripSub = _ridesRepo.watch(tripId!).listen(_onTripUpdate);
    } catch (e) {
      errorMessage = 'error_generic|$e';
      notifyListeners();
      return;
    }

    _startCycle();
  }

  double get currentRadiusKm => _radiusForCycle(cycle);

  double _radiusForCycle(int c) {
    switch (c) {
      case 0:
        return 3.0;
      case 1:
        return 5.0;
      case 2:
        return 7.0;
      default:
        return 7.0;
    }
  }

  void _startCycle() {
    _loadDriversInRadius(currentRadiusKm);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isDisposed) return;
      // Ҳайдовчи трипни банд қилиб қарор кутаётганда — сиклни музлатамиз
      // (кенгайтирмаймиз ва "топилмади" деб тугатмаймиз).
      if (driverReserved) {
        notifyListeners();
        return;
      }
      seconds--;
      if (seconds <= 0) {
        _nextCycle();
      } else {
        notifyListeners();
      }
    });
  }

  Future<void> _nextCycle() async {
    if (cycle >= 2) {
      _noDriversFound();
      return;
    }
    cycle++;
    seconds = 30;
    notifyListeners();

    if (tripId != null) {
      try {
        await _ridesRepo.updateSearchRadius(tripId!, currentRadiusKm);
      } catch (_) {}
    }
    await _loadDriversInRadius(currentRadiusKm);
  }

  Future<void> _loadDriversInRadius(double radiusKm) async {
    if (_fromLat == 0 && _fromLng == 0) {
      if (!_isDisposed) {
        drivers = const [];
        notifyListeners();
      }
      return;
    }
    try {
      final all = await _driverRepo.getAvailable();
      final nearby = <NearbyDriver>[];
      for (final d in all) {
        final dist = LocationService.distanceKm(
            _fromLat, _fromLng, d.lat, d.lng);
        if (dist <= radiusKm) {
          nearby.add(NearbyDriver(driver: d, distanceKm: dist));
        }
      }
      nearby.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
      if (!_isDisposed) {
        drivers = nearby;
        notifyListeners();
      }
    } catch (_) {}
  }

  // ── Trip kuzatuvchisidan kelgan yangiliklar ─────────────────────────
  void _onTripUpdate(ActiveTrip trip) {
    if (_isDisposed) return;

    if (trip.isCancelled || trip.status == 'expired') {
      _timer?.cancel();
      isSearching = false;
      driverReserved = false;
      errorMessage = 'local_search_ended_cancelled';
      notifyListeners();
      return;
    }

    // Қабул қилинди
    if (trip.isAccepted && acceptedTrip == null) {
      acceptedTrip = trip;
      driverReserved = false;
      _timer?.cancel();
      _tripSub?.cancel();
      notifyListeners();
      return;
    }

    // Ҳайдовчи банд қилди (reserved) — "Ҳайдовчи топилди, кутилмоқда".
    if (trip.isReserved && !driverReserved) {
      driverReserved = true;
      notifyListeners();
      return;
    }
    // Банд бекор қилинди (ҳайдовчи рад этди ёки таймаут) — қидирув давом этади,
    // бошқа ҳайдовчилар трипни яна кўради.
    if (!trip.isReserved && driverReserved && !trip.isAccepted) {
      driverReserved = false;
      notifyListeners();
    }
  }

  void _noDriversFound() {
    _timer?.cancel();
    isSearching = false;
    notifyListeners();
    // Trip "expired" sifatida bekor qilish.
    _cancelTripSilently();
  }

  // ── Dialog ko'rsatilganidan keyin "iste'mol qilish" ─────────────────
  ActiveTrip? consumeAcceptedTrip() {
    final t = acceptedTrip;
    acceptedTrip = null;
    return t;
  }

  String? consumeError() {
    final m = errorMessage;
    errorMessage = null;
    return m;
  }

  /// Foydalanuvchi orqaga tugmasini bosganda.
  Future<void> cancelByUser() async {
    if (_isCancelled) return;
    _isCancelled = true;
    _timer?.cancel();
    _tripSub?.cancel();
    if (tripId != null) {
      try {
        await _ridesRepo.cancelSearch(tripId: tripId!);
      } catch (_) {}
    }
  }

  /// Fire-and-forget — dispose paytida ham чақириладi.
  void _cancelTripSilently() {
    if (_isCancelled || tripId == null) return;
    _isCancelled = true;
    _ridesRepo.cancelSearch(tripId: tripId!).catchError((_) {});
  }

  @override
  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    _tripSub?.cancel();
    _cancelTripSilently();
    super.dispose();
  }
}
