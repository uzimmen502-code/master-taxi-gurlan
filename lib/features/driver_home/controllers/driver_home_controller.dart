import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/active_trip.dart';
import '../../../models/driver_session.dart';
import '../../../models/queue_entry.dart';
import '../../../models/trip_request.dart';
import '../../../repositories/driver_repository.dart';
import '../../../repositories/queue_repository.dart';
import '../../../repositories/rides_repository.dart';
import '../../../repositories/schedules_repository.dart';
import '../../../services/background_gps_service.dart';
import '../../../services/balance_service.dart';

/// Ҳайдовчи бош экранининг controller'и — сессия, онлайн, навбат, буюртмалар.
class DriverHomeController extends ChangeNotifier {
  DriverHomeController({
    required DriverRepository driverRepo,
    required SchedulesRepository schedulesRepo,
    required RidesRepository ridesRepo,
    required QueueRepository queueRepo,
  })  : _driverRepo = driverRepo,
        _schedulesRepo = schedulesRepo,
        _ridesRepo = ridesRepo,
        _queueRepo = queueRepo {
    _init();
  }

  final DriverRepository _driverRepo;
  final SchedulesRepository _schedulesRepo;
  final RidesRepository _ridesRepo;
  final QueueRepository _queueRepo;

  // ─── Состояние ─────────────────────────────────────────────────────
  DriverSession session = const DriverSession();
  bool isOnline = false;
  bool isBusy = false;
  bool hasInternet = true;
  bool hasScheduleToday = false;

  /// `secsLeft` ҳисоблаш учун охирги тиклаш вақти.
  List<TripRequest> activeRequests = const [];
  TripRequest? acceptedRide;

  int seatsLeft = 0;
  int totalSeats = 0;

  List<QueueEntry> queueList = const [];
  int queuePosition = 0;

  // ─── Subscriptions ────────────────────────────────────────────────
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  StreamSubscription<List<ActiveTrip>>? _tripsSub;
  StreamSubscription<List<QueueEntry>>? _queueSub;
  StreamSubscription<Position>? _gpsSub;

  double? _driverLat;
  double? _driverLng;

  /// Стрим янги request топилганда UI диалог кўрсатиш учун —
  /// `_tripsSub` ичида берилади. View подпиёса бўлади.
  final _newRequestController = StreamController<TripRequest>.broadcast();
  Stream<TripRequest> get onNewRequest => _newRequestController.stream;

  /// "Бўш ўрин қолмади" дан огоҳлантириш учун — `_acceptRide` тугагандан кейин.
  final _seatsFullController = StreamController<void>.broadcast();
  Stream<void> get onSeatsFull => _seatsFullController.stream;

  bool _disposed = false;

  String get _todayDateStr {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  // ─── Init ──────────────────────────────────────────────────────────
  Future<void> _init() async {
    await _loadSession();
    _listenConnectivity();
  }

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final phone = prefs.getString('user_phone') ?? '';
    session = DriverSession(
      name: prefs.getString('user_name') ?? 'Ҳайдовчи',
      gender: prefs.getString('user_gender') ?? 'male',
      phone: phone,
      carModel: prefs.getString('car_model') ?? '',
      carPlate: prefs.getString('car_plate') ?? '',
      taxiType: prefs.getString('taxi_type') ?? 'alone',
      driverId: phone.replaceAll(RegExp(r'[^\d]'), ''),
      todayTrips: prefs.getInt('today_trips') ?? 0,
      todayEarnings: prefs.getInt('today_earnings') ?? 0,
      totalTrips: prefs.getInt('total_trips') ?? 0,
    );
    notifyListeners();

    await _schedulesRepo.closeExpiredForDriver(session.driverId);
    await _checkTodaySchedule();
    if (session.carModel.isNotEmpty && session.driverId.isNotEmpty) {
      await _driverRepo.upsertProfile(
        uid: session.driverId,
        name: session.name,
        phone: session.phone,
        car: session.carModel,
        plate: session.carPlate,
        taxiType: session.taxiType,
      );
    }
  }

  void _listenConnectivity() {
    _connSub = Connectivity().onConnectivityChanged.listen((r) {
      hasInternet = !r.contains(ConnectivityResult.none);
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> _checkTodaySchedule() async {
    if (session.driverId.isEmpty) return;
    final sched = await _schedulesRepo.getTodayActiveForDriverAnyType(
      driverId: session.driverId,
      date: _todayDateStr,
    );
    if (sched == null) {
      hasScheduleToday = false;
      seatsLeft = 0;
      totalSeats = 0;
    } else {
      hasScheduleToday = true;
      seatsLeft = sched.seatsLeft;
      totalSeats = sched.seats;
    }
    notifyListeners();
  }

  /// Ишни бошлаш экранидан қайтгандан кейин қайта чақирилади.
  Future<void> refreshTodaySchedule() => _checkTodaySchedule();

  // ─── Онлайн/оффлайн ────────────────────────────────────────────────
  Future<({bool success, String? error})> toggleOnline() async {
    try {
      await _schedulesRepo.closeExpiredForDriver(session.driverId);
      final newStatus = !isOnline;
      if (newStatus) {
        final hasValid = await _schedulesRepo.hasActiveToday(
          driverId: session.driverId,
          date: _todayDateStr,
        );
        if (!hasValid) {
          return (
            success: false,
            error: '⚠️ Аввал "ИШНИ БОШЛАШ" ни босинг!',
          );
        }
      }
      isOnline = newStatus;
      if (!newStatus) {
        activeRequests = const [];
        acceptedRide = null;
        isBusy = false;
        _tripsSub?.cancel();
      }
      notifyListeners();
      if (newStatus) {
        await _goOnline();
      } else {
        await _goOffline();
      }
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Хатолик: $e');
    }
  }

  Future<void> _goOnline() async {
    if (session.driverId.isEmpty) return;
    Position? pos;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm != LocationPermission.denied &&
          perm != LocationPermission.deniedForever) {
        pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 8));
      }
    } catch (_) {}

    await _driverRepo.goOnline(
      uid: session.driverId,
      name: session.name,
      phone: session.phone,
      taxiType: session.taxiType,
      lat: pos?.latitude,
      lng: pos?.longitude,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('driver_online', true);
    try {
      await BackgroundGpsService.start();
    } catch (_) {}

    _startGpsTracking();
    _listenQueue();
    await _queueRepo.join(
      driverId: session.driverId,
      driverName: session.name,
      driverPhone: session.phone,
      car: session.carModel,
      plate: session.carPlate,
      taxiType: session.taxiType,
      date: _todayDateStr,
      lat: pos?.latitude,
      lng: pos?.longitude,
    );
    _listenToTrips();
  }

  Future<void> _goOffline() async {
    if (session.driverId.isEmpty) return;
    _gpsSub?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('driver_online', false);
    try {
      await BackgroundGpsService.stop();
    } catch (_) {}
    await _queueRepo.leave(session.driverId);
    _queueSub?.cancel();
    await _driverRepo.goOffline(session.driverId);
  }

  void _startGpsTracking() {
    _gpsSub?.cancel();
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 20),
    ).listen((pos) {
      _driverLat = pos.latitude;
      _driverLng = pos.longitude;
      if (!isOnline || session.driverId.isEmpty) return;
      _driverRepo.updateLocation(
          uid: session.driverId, lat: pos.latitude, lng: pos.longitude);
    });
  }

  // ─── Навбат ────────────────────────────────────────────────────────
  void _listenQueue() {
    _queueSub?.cancel();
    _queueSub = _queueRepo.watchByType(session.taxiType).listen((list) {
      queueList = list;
      int pos = 0;
      for (int i = 0; i < list.length; i++) {
        if (list[i].driverId == session.driverId) {
          pos = i + 1;
          break;
        }
      }
      queuePosition = pos;
      if (pos > 0) {
        _queueRepo.saveLastPosition(
            driverId: session.driverId, position: pos);
      }
      notifyListeners();
    });
  }

  // ─── Трипларни кузатиш ────────────────────────────────────────────
  void _listenToTrips() {
    _tripsSub?.cancel();
    _tripsSub = _ridesRepo.watchPendingTrips().listen((trips) {
      final now = DateTime.now();
      final filtered = trips.where((t) {
        if (t.taxiType == 'marshrut') return false;
        if (t.createdAt != null) {
          final age = now.difference(t.createdAt!);
          if (age.inMinutes >= 3) return false;
        }
        return _matchesTaxiType(t.taxiType);
      }).toList();

      final list = filtered.map((t) {
        int secs = 180;
        if (t.createdAt != null) {
          secs = (180 - now.difference(t.createdAt!).inSeconds)
              .clamp(0, 180);
        }
        double distKm = 0;
        if (_driverLat != null &&
            _driverLng != null &&
            t.fromLat != 0 &&
            t.fromLng != 0) {
          distKm = Geolocator.distanceBetween(
                _driverLat!,
                _driverLng!,
                t.fromLat,
                t.fromLng,
              ) /
              1000;
        }
        return TripRequest(
          id: t.id,
          userPhone: t.userPhone,
          userName: t.userName,
          userGender: t.userGender,
          userBirthDate: t.userBirthDate,
          fromLat: t.fromLat,
          fromLng: t.fromLng,
          distanceKm: distKm,
          reservedBy: t.reservedBy,
          from: t.fromAddr,
          to: t.toAddr,
          taxiType: t.taxiType,
          secsLeft: secs,
          scheduleId: t.scheduleId,
          targetDriverId: t.targetDriverId,
        );
      }).toList();

      activeRequests = list;
      notifyListeners();
      if (list.isNotEmpty && !isBusy && acceptedRide == null) {
        _newRequestController.add(list.first);
      }
    });
  }

  bool _matchesTaxiType(String tripTaxiType) {
    if (session.taxiType == 'both') return true;
    if (session.taxiType == tripTaxiType) return true;
    // Йўловчи маҳаллий модул `taxiType: 'local'` ёзади; ҳайдовчи prefs — `'alone'`.
    final s = session.taxiType;
    final t = tripTaxiType;
    if ((s == 'alone' && t == 'local') || (s == 'local' && t == 'alone')) {
      return true;
    }
    return false;
  }

  // ─── Қабул қилиш / рад этиш ──────────────────────────────────────
  Future<({bool success, String? error})> acceptRide(TripRequest ride) async {
    final result = await _ridesRepo.acceptRide(
      tripId: ride.id,
      driverId: session.driverId,
      driverName: session.name,
      driverPhone: session.phone,
      driverCar: session.carModel,
      driverPlate: session.carPlate,
      scheduleId: ride.scheduleId,
      taxiType: ride.taxiType,
    );
    if (!result.success) {
      if (result.errorCode == 'no_seats') {
        return (success: false, error: '⚠️ Ўрин қолмаган');
      }
      return (success: false, error: '⚠️ Аллақачон қабул қилинган');
    }

    // Marshrut'дан ташқари — schedule'да scheduleId бўлса камайтириш
    if (ride.taxiType != 'marshrut' && ride.scheduleId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('schedules')
            .doc(ride.scheduleId)
            .update({'seatsLeft': FieldValue.increment(-1)});
      } catch (_) {}
    }
    await _driverRepo.decrementSeats(session.driverId);

    final newSeats = seatsLeft - 1;
    await _queueRepo.decrementSeats(
        driverId: session.driverId, currentSeats: seatsLeft);

    acceptedRide = ride;
    isBusy = true;
    seatsLeft = newSeats.clamp(0, totalSeats);
    activeRequests = activeRequests.where((r) => r.id != ride.id).toList();
    notifyListeners();

    if (newSeats <= 0) {
      _seatsFullController.add(null);
    }
    return (success: true, error: null);
  }

  Future<void> rejectRide(TripRequest ride) async {
    await _ridesRepo.rejectRide(
        tripId: ride.id, driverId: session.driverId);
  }

  // ─── Сафарни якунлаш ─────────────────────────────────────────────
  Future<int> finishRide({
    required int fare,
    required int cashPaid,
  }) async {
    final ride = acceptedRide;
    if (ride == null) return 0;
    _gpsSub?.cancel();
    await _ridesRepo.finishTrip(
        tripId: ride.id, fare: fare, cashPaid: cashPaid);

    if (ride.userPhone.isNotEmpty && cashPaid > fare) {
      try {
        await BalanceService.creditChange(
          userPhone: ride.userPhone,
          orderTotal: fare,
          cashPaid: cashPaid,
          refType: 'trip',
          refId: ride.id,
          module: session.taxiType,
          idempotencyKey: 'change_trip_${ride.id}',
          operatorPhone: session.phone,
        );
      } catch (e, st) {
        debugPrint('creditChange: $e\n$st');
      }
    }

    session = session.copyWith(
      todayTrips: session.todayTrips + 1,
      totalTrips: session.totalTrips + 1,
      todayEarnings: session.todayEarnings + fare,
    );
    acceptedRide = null;
    isBusy = false;
    notifyListeners();
    await _saveStats();
    return fare;
  }

  Future<void> _saveStats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('today_trips', session.todayTrips);
    await prefs.setInt('today_earnings', session.todayEarnings);
    await prefs.setInt('total_trips', session.totalTrips);
  }

  // ─── Бўш ўрин ────────────────────────────────────────────────────
  Future<({bool success, String? error})> addPassenger() async {
    if (session.driverId.isEmpty) return (success: false, error: null);
    final newSeats = await _schedulesRepo.adjustSeatsToday(
      driverId: session.driverId,
      date: _todayDateStr,
      delta: -1,
    );
    if (newSeats == null) return (success: false, error: null);
    if (newSeats < 0) {
      return (success: false, error: '⚠️ Бўш ўрин йўқ');
    }
    await _driverRepo.decrementSeats(session.driverId);
    await _queueRepo.decrementSeats(
        driverId: session.driverId, currentSeats: seatsLeft);
    seatsLeft = (newSeats).clamp(0, totalSeats);
    notifyListeners();
    return (success: true, error: '✅ +1 кўча йўловчи (қолди: $seatsLeft)');
  }

  Future<({bool success, String? error})> removePassenger() async {
    if (session.driverId.isEmpty) return (success: false, error: null);
    if (seatsLeft >= totalSeats) {
      return (success: false, error: 'Барча ўринлар бўш');
    }
    final newSeats = await _schedulesRepo.adjustSeatsToday(
      driverId: session.driverId,
      date: _todayDateStr,
      delta: 1,
    );
    if (newSeats == null) return (success: false, error: null);
    await _driverRepo.incrementSeats(session.driverId);
    await _queueRepo.incrementSeats(session.driverId);
    seatsLeft = newSeats.clamp(0, totalSeats);
    notifyListeners();
    return (success: true, error: '✅ Йўловчи камайтирилди');
  }

  // ─── Иш кунини якунлаш ──────────────────────────────────────────
  Future<void> endWorkDay() async {
    if (session.driverId.isEmpty) return;
    await _schedulesRepo.endTodayWork(
        driverId: session.driverId, date: _todayDateStr);
    await _driverRepo.markUnavailable(session.driverId);
    if (isOnline) {
      isOnline = false;
      await _goOffline();
    }
    await _queueRepo.clearLastPosition(session.driverId);
    await _checkTodaySchedule();
  }

  @override
  void dispose() {
    _disposed = true;
    _connSub?.cancel();
    _tripsSub?.cancel();
    _queueSub?.cancel();
    _gpsSub?.cancel();
    _newRequestController.close();
    _seatsFullController.close();
    if (isOnline) _driverRepo.goOffline(session.driverId);
    super.dispose();
  }
}
