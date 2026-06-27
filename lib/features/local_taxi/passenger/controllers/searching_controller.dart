import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../models/active_trip.dart';
import '../../../../models/nearby_driver.dart';
import '../../../../repositories/driver_repository.dart';
import '../../../../repositories/rides_repository.dart';
import '../../../../services/location_service.dart';
import '../../services/price_service.dart';

/// Yo'lovchining "haydovchi qidirish" oqimini boshqaradi.
///
/// 3 ta sikl (har biri 20 soniya): 3 km → 5 km → 7 km.
/// Hech kim qabul qilmasa — bo'sh ekran + cancel.
/// Haydovchi qabul qilganda — trip status `accepted` bo'ladi, controller buni
/// `acceptedTrip` orqali xabar beradi (UI dialog ko'rsatadi).
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
  bool driverReserved = false;

  /// Hozir taklif yuborilgan haydovchining UID'si. Bo'sh — hech kim
  /// tanlanmagan. UI shu ID bo'yicha tanlangan kartaga "yuborildi"
  /// belgisini chizadi.
  String pendingDriverId = '';

  /// Oxirgi tanlangan haydovchining UID'si (driver tomonidan rad etilgan/timeout
  /// bo'lsa, biz bilan: shu drayverni qayta tanlash mumkin emas, lekin boshqasini
  /// tanlasa bo'ladi). UI grey-out qilish uchun ishlatadi.
  final Set<String> rejectedByIds = <String>{};

  String? errorMessage;

  Timer? _timer;
  StreamSubscription<ActiveTrip>? _tripSub;

  // ── Boshlash ──────────────────────────────────────────────────────
  Future<void> start() async {
    await PriceService.loadPrices();

    final prefs = await SharedPreferences.getInstance();
    _userPhone = prefs.getString('user_phone') ?? '';
    _userName = prefs.getString('user_name') ?? '';
    _userGender = prefs.getString('user_gender') ?? '';
    _userBirthDate = prefs.getString('user_birth_date') ?? '';

    try {
      final coords = await _locationService.getCurrentCoords();
      _fromLat = coords.lat;
      _fromLng = coords.lng;
    } on LocationException {
      // GPS olinmadi — koordinatasiz davom etamiz (drivers list bo'sh bo'ladi).
    }

    try {
      final resumeId = existingTripId?.trim() ?? '';
      if (resumeId.isNotEmpty) {
        tripId = resumeId;
        final existing = await _ridesRepo.getTrip(resumeId);
        if (existing != null) {
          _fromLat = existing.fromLat;
          _fromLng = existing.fromLng;
        }
      } else {
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
    // GPS yo'q — barcha mavjud haydovchilarni ko'rsatamiz (radius filtrsiz)
    if (_fromLat == 0 && _fromLng == 0) {
      try {
        final all = await _driverRepo.getAvailable();
        if (!_isDisposed) {
          drivers = all
              .map((d) => NearbyDriver(driver: d, distanceKm: 0))
              .toList();
          notifyListeners();
        }
      } catch (_) {}
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
    // Банд бекор қилинди — қидирув давом этади.
    if (!trip.isReserved && driverReserved && !trip.isAccepted) {
      driverReserved = false;
      notifyListeners();
    }

    // Ҳайдовчи status: rejected қилди
    if (trip.isRejected && pendingDriverId.isNotEmpty) {
      rejectedByIds.add(pendingDriverId);
      pendingDriverId = '';
      errorMessage = 'driver_rejected_pick_another';
      notifyListeners();
      return;
    }

    // Ҳайдовчи targetDriverId'ни бўшатди (timeout ёки рад — eski oqim)
    if (pendingDriverId.isNotEmpty && trip.targetDriverId.isEmpty) {
      rejectedByIds.add(pendingDriverId);
      pendingDriverId = '';
      errorMessage = 'driver_rejected_pick_another';
      notifyListeners();
    }
  }

  /// Yo'lovchi ro'yxatdan haydovchini tanlaydi — `trips/{id}.targetDriverId`
  /// shu UID'ga set qilinadi. Driver app o'z `HomeScreen`'idagi
  /// `TripRequestScreen`'ni avtomatik ochadi.
  Future<void> selectDriver(NearbyDriver d) async {
    if (_isDisposed || tripId == null) return;
    if (pendingDriverId.isNotEmpty) return; // boshqa drayverga so'rov yuborilgan
    if (rejectedByIds.contains(d.driver.id)) return;
    pendingDriverId = d.driver.id;
    notifyListeners();
    try {
      await _ridesRepo.targetDriver(
        tripId: tripId!,
        driverId: d.driver.id,
      );
    } catch (e) {
      pendingDriverId = '';
      errorMessage = 'send_to_driver_failed';
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
