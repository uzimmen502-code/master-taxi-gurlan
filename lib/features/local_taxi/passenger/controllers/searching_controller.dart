import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/service_config_holder.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/active_trip.dart';
import '../../../../models/nearby_driver.dart';
import '../../../../repositories/driver_repository.dart';
import '../../../../repositories/local_taxi_block_repository.dart';
import '../../../../repositories/rides_repository.dart';
import '../../../../services/location_service.dart';
import '../../services/local_trip_fare_lock_service.dart';

/// Yo'lovchining "haydovchi qidirish" oqimini boshqaradi (BROADCAST modeli).
///
/// Yo'lovchi haydovchini QO'LDA tanlamaydi. `trips/{id}` `searching` holatida
/// yaratiladi va radius bo'yicha kengayadi (3 km → 5 km → 7 km, har biri 30s);
/// radius `trips.radiusKm` ga yoziladi — atrofdagi BARCHA haydovchilar shu
/// radius ichida so'rovni ko'radi (`watchPendingTrips` + radius gate).
/// Birinchi "Qabul" bosgan haydovchi tripni to'g'ridan `accepted` qiladi
/// (first-accept-wins). Hech kim qabul qilmasa — bo'sh ekran + cancel.
class SearchingController extends ChangeNotifier {
  SearchingController({
    required RidesRepository ridesRepo,
    required DriverRepository driverRepo,
    required LocationService locationService,
    required this.from,
    required this.to,
    required this.taxiType,
    this.existingTripId,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
    LocalTaxiBlockRepository? blockRepo,
    LocalTripFareLockService? fareLock,
  })  : _ridesRepo = ridesRepo,
        _driverRepo = driverRepo,
        _locationService = locationService,
        _blockRepo = blockRepo ?? LocalTaxiBlockRepository(),
        _fareLock = fareLock ?? LocalTripFareLockService();

  /// Mavjud qidiruv tripini tiklash (yangi trip yaratilmaydi).
  final String? existingTripId;

  /// Xarita/GPS dan aniq pickup (berilsa fresh GPS o'rniga ishlatiladi).
  final double? pickupLat;
  final double? pickupLng;

  /// Ixtiyoriy destination (berilsa yo'lkira qulflanadi).
  final double? dropoffLat;
  final double? dropoffLng;

  final RidesRepository _ridesRepo;
  final DriverRepository _driverRepo;
  final LocationService _locationService;
  final LocalTaxiBlockRepository _blockRepo;
  final LocalTripFareLockService _fareLock;

  final String from;
  final String to;
  final String taxiType;

  // ── State ──────────────────────────────────────────────────────────
  String? tripId;

  /// Bitta buyurtma = bitta id: tarmoq qayta urinsa ham server ikkinchi
  /// trip yaratmaydi (`createLocalTaxiTrip` idempotent).
  final String _requestId = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${Random().nextInt(1 << 30).toRadixString(36)}';
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

  /// Haydovchi qabul qilganda faol safar ekraniga o'tiladi — dispose bekor qilmasin.
  bool _handedOffToActiveTrip = false;

  List<NearbyDriver> drivers = const [];

  /// Haydovchi qabul qilganda to'ladi. UI buni "iste'mol" qilib dialog ko'rsatadi.
  ActiveTrip? acceptedTrip;

  String? errorMessage;

  Timer? _timer;
  Timer? _driversRefreshTimer;
  StreamSubscription<ActiveTrip>? _tripSub;

  // ── Boshlash ──────────────────────────────────────────────────────
  Future<void> start() async {
    final prefsLat = pickupLat;
    final prefsLng = pickupLng;
    if (prefsLat != null &&
        prefsLng != null &&
        (prefsLat.abs() > 1e-6 || prefsLng.abs() > 1e-6)) {
      _fromLat = prefsLat;
      _fromLng = prefsLng;
    }

    final prefs = await SharedPreferences.getInstance();
    _userPhone = prefs.getString('user_phone') ?? '';
    _userName = prefs.getString('user_name') ?? '';
    _userGender = prefs.getString('user_gender') ?? '';
    _userBirthDate = prefs.getString('user_birth_date') ?? '';

    try {
      final phone = phoneDigits(_userPhone);
      if (phone.length >= 9 && await _blockRepo.isBlocked(phone)) {
        final until = await _blockRepo.getBlockedUntil(phone);
        final mins = until == null
            ? 1
            : until.difference(DateTime.now()).inMinutes.clamp(1, 9999) + 1;
        errorMessage = 'local_taxi_block_active|$mins';
        isSearching = false;
        notifyListeners();
        return;
      }

      final resumeId = existingTripId?.trim() ?? '';
      if (resumeId.isNotEmpty) {
        tripId = resumeId;
        final existing = await _ridesRepo.getTrip(resumeId);
        if (existing != null) {
          _fromLat = existing.fromLat;
          _fromLng = existing.fromLng;
          // Qayta ochilganda radius 3 km ga qaytib, 7 km ni 5 km bilan
          // ustidan yozmasin.
          cycle = existing.radiusKm >= 7
              ? 2
              : existing.radiusKm >= 5
                  ? 1
                  : 0;
        }
      }

      if (_fromLat == 0 && _fromLng == 0) {
        try {
          final coords = await _locationService.getFreshCoords();
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
        // Manzil majburiy, narxni server qotiradi (ega qarori 2026-10-07).
        final dLat = dropoffLat;
        final dLng = dropoffLng;
        if (dLat == null ||
            dLng == null ||
            (dLat.abs() < 1e-6 && dLng.abs() < 1e-6) ||
            to.trim().isEmpty) {
          errorMessage = 'local_destination_required';
          isSearching = false;
          notifyListeners();
          return;
        }
        try {
          final created = await _fareLock.createTrip(
            requestId: _requestId,
            fromAddr: from,
            fromLat: _fromLat,
            fromLng: _fromLng,
            toAddr: to,
            toLat: dLat,
            toLng: dLng,
            userName: _userName,
            userGender: _userGender,
            userBirthDate: _userBirthDate,
            report: ServiceConfigHolder.reportStamp(),
          );
          tripId = created.tripId;
        } catch (e) {
          debugPrint('createLocalTaxiTrip: $e');
          errorMessage = LocalTripFareLockService.errorKey(e);
          isSearching = false;
          notifyListeners();
          return;
        }
        // Ekran yopilgan bo'lsa — trip'ni qoldirmaymiz.
        if (_isDisposed) {
          _ridesRepo.cancelSearch(tripId: tripId!).then((_) {},
              onError: (Object e) {
            debugPrint('cancelSearch after dispose: $e');
          });
          return;
        }
      }
      _tripSub = _ridesRepo.watch(tripId!).listen(_onTripUpdate);
    } catch (e) {
      debugPrint('searching start: $e');
      errorMessage = 'local_order_failed';
      notifyListeners();
      return;
    }
    if (_isDisposed) {
      _tripSub?.cancel();
      return;
    }

    _startCycle();
  }

  double get currentRadiusKm => _radiusForCycle(cycle);

  double get fromLat => _fromLat;
  double get fromLng => _fromLng;

  bool get hasPickupCoords => _fromLat != 0 || _fromLng != 0;

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
    _driversRefreshTimer?.cancel();
    _driversRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isDisposed || !isSearching) return;
      _loadDriversInRadius(currentRadiusKm);
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isDisposed) return;
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
      _driversRefreshTimer?.cancel();
      isSearching = false;
      errorMessage = 'local_search_ended_cancelled';
      notifyListeners();
      return;
    }

    if (trip.isAccepted && acceptedTrip == null) {
      acceptedTrip = trip;
      _handedOffToActiveTrip = true;
      _isCancelled = true;
      _timer?.cancel();
      _driversRefreshTimer?.cancel();
      _tripSub?.cancel();
      notifyListeners();
    }
  }

  void _noDriversFound() {
    _timer?.cancel();
    _driversRefreshTimer?.cancel();
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
  /// `true` — ekranni yopish mumkin; `false` — haydovchi shu lahzada qabul
  /// qilgan (trip `accepted`), ekran faol safarga o'tadi (yopilmaydi —
  /// aks holda haydovchi bo'sh joyga borardi).
  Future<bool> cancelByUser() async {
    if (_isCancelled) return true;
    _isCancelled = true;
    _timer?.cancel();
    _driversRefreshTimer?.cancel();
    _tripSub?.cancel();
    final id = tripId;
    if (id == null) return true;
    try {
      final status = await _ridesRepo.cancelSearch(tripId: id);
      if (status == 'accepted') {
        final trip = await _ridesRepo.getTrip(id);
        if (trip != null && trip.isAccepted && !_isDisposed) {
          acceptedTrip = trip;
          _handedOffToActiveTrip = true;
          errorMessage = 'local_cancel_too_late_accepted';
          notifyListeners();
          return false;
        }
      }
    } catch (e) {
      debugPrint('cancelSearch: $e');
      // dispose'dagi jim bekor qilish yana urinsin.
      _isCancelled = false;
    }
    return true;
  }

  /// Fire-and-forget — dispose paytida; хатони log қилади.
  void _cancelTripSilently() {
    if (_isCancelled || tripId == null) return;
    _isCancelled = true;
    _ridesRepo.cancelSearch(tripId: tripId!).then((_) {}, onError: (Object e) {
      debugPrint('cancelSearch silent: $e');
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    _driversRefreshTimer?.cancel();
    _tripSub?.cancel();
    if (!_handedOffToActiveTrip) {
      _cancelTripSilently();
    }
    super.dispose();
  }
}
