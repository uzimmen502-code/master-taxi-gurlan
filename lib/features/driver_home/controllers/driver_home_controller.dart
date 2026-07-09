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
import '../../../utils/fare_calculator.dart';
import '../../../repositories/driver_repository.dart';
import '../../../repositories/queue_repository.dart';
import '../../../repositories/rides_repository.dart';
import '../../../repositories/schedules_repository.dart';
import '../../../core/utils/formatters.dart';
import '../../../services/background_gps_service.dart';
import '../../../services/deferred_settlement_queue.dart';
import '../../../services/trip_change_settlement.dart';

/// Haydovchi GPS profili — batareya uchun moslashtirilgan.
enum _DriverGpsProfile { waiting, offers, trip }

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
  StreamSubscription<List<ActiveTrip>>? _acceptedTripsSub;
  StreamSubscription<List<QueueEntry>>? _queueSub;
  StreamSubscription<Position>? _gpsSub;

  double? _driverLat;
  double? _driverLng;
  double? _lastWrittenLat;
  double? _lastWrittenLng;

  /// Kutish / chaqiruv / safar — GPS tezligi va Firestore yozuvlari.
  _DriverGpsProfile _gpsProfile = _DriverGpsProfile.waiting;

  double? get driverLat => _driverLat;
  double? get driverLng => _driverLng;

  TripRequest? get nearestRequest =>
      activeRequests.isNotEmpty ? activeRequests.first : null;

  bool get isLocalAcceptedRide {
    final r = acceptedRide;
    if (r == null) return false;
    return r.taxiType == 'local' || r.taxiType == 'alone';
  }

  /// Бу ҳайдовчи "Рад" қилиб локал равишда яширган трип ID'лари.
  /// Broadcast моделида рад этиш трипни ҳамма учун бекор қилмайди — фақат шу
  /// ҳайдовчининг рўйхатидан олиб ташлайди (бошқалар кўришда давом этади).
  final Set<String> _dismissedTripIds = <String>{};

  /// Стрим янги request топилганда UI диалог кўрсатиш учун —
  /// `_tripsSub` ичида берилади. View подпиёса бўлади.
  final _newRequestController = StreamController<TripRequest>.broadcast();
  Stream<TripRequest> get onNewRequest => _newRequestController.stream;

  /// "Бўш ўрин қолмади" дан огоҳлантириш учун — `_acceptRide` тугагандан кейин.
  final _seatsFullController = StreamController<void>.broadcast();
  Stream<void> get onSeatsFull => _seatsFullController.stream;

  /// Yo'lovchi qabul qilingan safarni bekor qilganda UI xabari.
  final _passengerCancelController = StreamController<void>.broadcast();
  Stream<void> get onPassengerCancelled => _passengerCancelController.stream;

  /// `finishRide` / `abandonRide` paytida noto'g'ri cancel xabari chiqmasligi учун.
  String? _finishingTripId;
  String? _releasingTripId;

  /// Oxirgi qaytim settlement natijasi (UI snackbar uchun).
  TripChangeSettlementOutcome? lastSettlementOutcome;

  bool _disposed = false;

  String get _todayDateStr {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  // ─── Init ──────────────────────────────────────────────────────────
  Future<void> _init() async {
    await _loadSession();
    await FareCalculator.loadPrices();
    _listenConnectivity();
    await _tryRestoreOnlineSession();
    // Ilova ochilishida — kutib qolgan deferred settlement'larni yuborish.
    unawaited(DeferredSettlementQueue.flush());
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
      final wasOffline = !hasInternet;
      hasInternet = !r.contains(ConnectivityResult.none);
      if (!_disposed) notifyListeners();
      // Internet qaytgach — kutib qolgan deferred settlement'larni yuborish.
      if (hasInternet && wasOffline) {
        unawaited(DeferredSettlementQueue.flush());
      }
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
  Future<void> _tryRestoreOnlineSession() async {
    if (session.driverId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('driver_online') ?? false)) return;

    final hasValid = await _schedulesRepo.hasActiveToday(
      driverId: session.driverId,
      date: _todayDateStr,
    );
    if (!hasValid) return;

    isOnline = true;
    notifyListeners();
    final onlineOk = await _goOnline();
    if (!onlineOk) {
      isOnline = false;
      notifyListeners();
    }
  }

  bool _isLocalTaxiTrip(ActiveTrip trip) =>
      trip.taxiType == 'local' || trip.taxiType == 'alone';

  TripRequest _tripRequestFromActiveTrip(ActiveTrip t) => TripRequest(
        id: t.id,
        userPhone: t.userPhone,
        userName: t.userName,
        userGender: t.userGender,
        userBirthDate: t.userBirthDate,
        fromLat: t.fromLat,
        fromLng: t.fromLng,
        from: t.fromAddr,
        to: t.toAddr,
        taxiType: t.taxiType,
        secsLeft: 0,
        scheduleId: t.scheduleId,
        targetDriverId: t.targetDriverId,
        reservedBy: t.reservedBy,
      );

  void _setAcceptedFromActiveTrip(ActiveTrip trip) {
    acceptedRide = _tripRequestFromActiveTrip(trip);
    isBusy = true;
    activeRequests =
        activeRequests.where((r) => r.id != trip.id).toList();
    _reconcileGpsProfile();
    notifyListeners();
  }

  Future<void> _releaseLocalAcceptedTripIfAny() async {
    final ride = acceptedRide;
    if (ride == null || !isLocalAcceptedRide) return;
    _releasingTripId = ride.id;
    try {
      await _ridesRepo.releaseAcceptedTrip(
        tripId: ride.id,
        driverId: session.driverId,
      );
    } catch (_) {}
    _releasingTripId = null;
    acceptedRide = null;
    isBusy = false;
    _reconcileGpsProfile();
    notifyListeners();
  }

  Future<void> _notifyPassengerCancelIfRemoved(String tripId) async {
    if (tripId.isEmpty) return;
    if (_finishingTripId == tripId || _releasingTripId == tripId) return;
    try {
      final trip = await _ridesRepo.getTrip(tripId);
      if (trip != null && trip.isPassengerCancelled) {
        _passengerCancelController.add(null);
      }
    } catch (_) {}
  }

  void _listenAcceptedTrips() {
    _acceptedTripsSub?.cancel();
    if (session.driverId.isEmpty) return;
    _acceptedTripsSub =
        _ridesRepo.watchAcceptedForDriver(session.driverId).listen((trips) {
      if (_disposed) return;
      final local =
          trips.where(_isLocalTaxiTrip).toList(growable: false);

      if (acceptedRide != null) {
        final still =
            local.any((t) => t.id == acceptedRide!.id);
        if (!still) {
          final removedId = acceptedRide!.id;
          acceptedRide = null;
          isBusy = false;
          _reconcileGpsProfile();
          notifyListeners();
          unawaited(_notifyPassengerCancelIfRemoved(removedId));
        }
        return;
      }

      if (local.isNotEmpty) {
        _setAcceptedFromActiveTrip(local.first);
      }
    });
  }

  /// Ишни бошлаш экранидан қайтгандан кейин қайта чақирилади.
  Future<void> refreshTodaySchedule() => _checkTodaySchedule();


  /// Маҳаллий такси (alone/local) учун "ИШНИ БОШЛАШ" — бир босишда:
  /// бугунги жадвални яратади (агар йўқ бўлса) ва онлайнга чиқаради.
  /// Ҳеч қандай экран ёки диалог очилмайди.
  Future<({bool success, String? error})> startLocalWork() async {
    if (session.driverId.isEmpty) {
      return (success: false, error: 'Ҳайдовчи топилмади');
    }
    try {
      if (!hasScheduleToday) {
        final now = DateTime.now();
        final midnight = DateTime(now.year, now.month, now.day, 23, 59, 59);
        await _schedulesRepo.registerDriverSchedule(
          driverId: session.driverId,
          taxiType: session.taxiType,
          driverName: session.name,
          driverPhone: session.phone,
          driverCar: session.carModel,
          driverPlate: session.carPlate,
          date: _todayDateStr,
          expiresAt: midnight,
          seats: 1,
          fromText: '',
          toText: '',
        );
        await _checkTodaySchedule();
      }
      if (!isOnline) {
        return await toggleOnline();
      }
      return (success: true, error: null);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('permission-denied')) {
        return (
          success: false,
          error: 'Firestore рухсати йўқ. Admin тасдиғини текширинг.'
        );
      }
      return (success: false, error: 'Хатолик: $e');
    }
  }

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
        if (isBusy && isLocalAcceptedRide) {
          await _releaseLocalAcceptedTripIfAny();
        } else {
          activeRequests = const [];
          acceptedRide = null;
          isBusy = false;
        }
        _tripsSub?.cancel();
        _acceptedTripsSub?.cancel();
      }
      notifyListeners();
      if (newStatus) {
        final onlineOk = await _goOnline();
        if (!onlineOk) {
          isOnline = false;
          notifyListeners();
          return (
            success: false,
            error:
                '⚠️ GPS aniqlanmadi. Online bo\'lish uchun joylashuvni yoqing.',
          );
        }
      } else {
        await _goOffline();
      }
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Хатолик: $e');
    }
  }

  Future<bool> _goOnline() async {
    if (session.driverId.isEmpty) return false;
    late final Position pos;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return false;
      }
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return false;
      pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 12)));
    } catch (_) {
      return false;
    }

    _driverLat = pos.latitude;
    _driverLng = pos.longitude;

    await _driverRepo.goOnline(
      uid: session.driverId,
      name: session.name,
      phone: session.phone,
      taxiType: session.taxiType,
      lat: pos.latitude,
      lng: pos.longitude,
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
      lat: pos.latitude,
      lng: pos.longitude,
    );
    _listenToTrips();
    _listenAcceptedTrips();
    return true;
  }

  Future<void> _goOffline() async {
    if (session.driverId.isEmpty) return;
    _gpsSub?.cancel();
    _acceptedTripsSub?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('driver_online', false);
    try {
      await BackgroundGpsService.stop();
    } catch (_) {}
    await _queueRepo.leave(session.driverId);
    _queueSub?.cancel();
    await _driverRepo.goOffline(session.driverId);
  }

  void _reconcileGpsProfile() {
    final next = isBusy
        ? _DriverGpsProfile.trip
        : activeRequests.isNotEmpty
            ? _DriverGpsProfile.offers
            : _DriverGpsProfile.waiting;
    if (next == _gpsProfile) return;
    _gpsProfile = next;
    if (isOnline) _startGpsTracking();
  }

  void _startGpsTracking() {
    _gpsSub?.cancel();
    final settings = switch (_gpsProfile) {
      _DriverGpsProfile.waiting => const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 60,
        ),
      _DriverGpsProfile.offers => const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 20,
        ),
      _DriverGpsProfile.trip => const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
    };
    _gpsSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) {
      _driverLat = pos.latitude;
      _driverLng = pos.longitude;
      if (!isOnline || session.driverId.isEmpty) return;

      final minWriteM = switch (_gpsProfile) {
        _DriverGpsProfile.waiting => 80.0,
        _DriverGpsProfile.offers => 25.0,
        _DriverGpsProfile.trip => 8.0,
      };
      if (_lastWrittenLat != null && _lastWrittenLng != null) {
        final moved = Geolocator.distanceBetween(
          _lastWrittenLat!,
          _lastWrittenLng!,
          pos.latitude,
          pos.longitude,
        );
        if (moved < minWriteM) return;
      }
      _lastWrittenLat = pos.latitude;
      _lastWrittenLng = pos.longitude;
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
    final lat = _driverLat;
    final lng = _driverLng;
    final stream = lat != null && lng != null
        ? _ridesRepo.watchPendingTripsNear(lat: lat, lng: lng)
        : _ridesRepo.watchPendingTrips();
    _tripsSub = stream.listen((trips) {
      final now = DateTime.now();
      final filtered = trips.where((t) {
        if (t.taxiType == 'marshrut') return false;
        if (_dismissedTripIds.contains(t.id)) return false;
        if (!t.isActiveSearchOffer) return false;
        if (!_matchesTaxiType(t.taxiType)) return false;
        // Radius gate: haydovchi faqat yo'lovchining joriy qidiruv radiusi
        // ichidagi buyurtmalarni ko'radi (0.5 km — GPS xatosi uchun bufer).
        if (_driverLat != null &&
            _driverLng != null &&
            t.fromLat != 0 &&
            t.fromLng != 0) {
          final dKm = Geolocator.distanceBetween(
                _driverLat!,
                _driverLng!,
                t.fromLat,
                t.fromLng,
              ) /
              1000;
          if (dKm > t.radiusKm + 0.5) return false;
        }
        return true;
      }).toList()
        ..sort((a, b) {
          final da = Geolocator.distanceBetween(
            _driverLat ?? 0,
            _driverLng ?? 0,
            a.fromLat,
            a.fromLng,
          );
          final db = Geolocator.distanceBetween(
            _driverLat ?? 0,
            _driverLng ?? 0,
            b.fromLat,
            b.fromLng,
          );
          return da.compareTo(db);
        });

      final list = filtered.map((t) {
        int secs = 0;
        if (t.expiresAt != null) {
          secs = t.expiresAt!.difference(now).inSeconds.clamp(0, 999);
        } else if (t.createdAt != null) {
          secs = (180 - now.difference(t.createdAt!).inSeconds).clamp(0, 180);
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
      _reconcileGpsProfile();
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

    // Local taxi (alone/local) — "ўрин" тушунчаси йўқ (битта ҳайдовчи,
    // битта йўловчи). Seats камайтириш фақат marshrut/schedule учун.
    final isLocalTaxi =
        ride.taxiType == 'alone' || ride.taxiType == 'local';

    if (!isLocalTaxi) {
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
      _reconcileGpsProfile();
      notifyListeners();

      if (newSeats <= 0) {
        _seatsFullController.add(null);
      }
      return (success: true, error: null);
    }

    // Local taxi — оддий қабул, seats'сиз.
    acceptedRide = ride;
    isBusy = true;
    activeRequests = activeRequests.where((r) => r.id != ride.id).toList();
    _reconcileGpsProfile();
    notifyListeners();
    return (success: true, error: null);
  }

  /// Local broadcast'да "Рад" — трипни ҳамма учун бекор қилмайди, фақат шу
  /// ҳайдовчининг рўйхатидан локал равишда олиб ташлайди. Трип `searching`
  /// ҳолатида қолади, бошқа ҳайдовчилар уни кўришда давом этади.
  void dismissRequest(TripRequest ride) {
    _dismissedTripIds.add(ride.id);
    activeRequests = activeRequests.where((r) => r.id != ride.id).toList();
    _reconcileGpsProfile();
    notifyListeners();
  }

  // ─── Сафарни якунлаш ─────────────────────────────────────────────
  Future<int> finishRide({
    required int fare,
    required int cashPaid,
  }) async {
    final ride = acceptedRide;
    if (ride == null) return 0;
    _finishingTripId = ride.id;
    _gpsSub?.cancel();
    await _ridesRepo.finishTrip(
        tripId: ride.id, fare: fare, cashPaid: cashPaid);

    lastSettlementOutcome = null;
    if (ride.userPhone.isNotEmpty && cashPaid > fare) {
      final change = cashPaid - fare;
      final opId = 'settle_trip_${ride.id}';
      lastSettlementOutcome = await TripChangeSettlement.settle(
        passengerPhone: canonicalPhoneId(ride.userPhone),
        tripId: ride.id,
        opId: opId,
        change: change,
      );
      if (lastSettlementOutcome!.status ==
          TripChangeSettlementStatus.failedPermanent) {
        debugPrint(
            'settlement: ${lastSettlementOutcome!.reasonCode} '
            '${lastSettlementOutcome!.userMessage}');
      }
    }

    session = session.copyWith(
      todayTrips: session.todayTrips + 1,
      totalTrips: session.totalTrips + 1,
      todayEarnings: session.todayEarnings + fare,
    );
    acceptedRide = null;
    isBusy = false;
    _reconcileGpsProfile();
    if (isOnline && _gpsSub == null) _startGpsTracking();
    notifyListeners();
    await _saveStats();
    _finishingTripId = null;
    return fare;
  }

  /// Сафарни тугатмасдан тарк этиш (back тугмаси) — трипни озод қилади.
  Future<void> abandonRide() async {
    final ride = acceptedRide;
    if (ride != null) {
      _releasingTripId = ride.id;
    }
    acceptedRide = null;
    isBusy = false;
    _reconcileGpsProfile();
    if (isOnline && _gpsSub == null) _startGpsTracking();
    notifyListeners();
    if (ride != null) {
      try {
        await _ridesRepo.releaseAcceptedTrip(
            tripId: ride.id, driverId: session.driverId);
      } catch (_) {}
      _releasingTripId = null;
    }
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
    if (isBusy && isLocalAcceptedRide) {
      await _releaseLocalAcceptedTripIfAny();
    }
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
    _acceptedTripsSub?.cancel();
    _queueSub?.cancel();
    _gpsSub?.cancel();
    _newRequestController.close();
    _seatsFullController.close();
    _passengerCancelController.close();
    if (isOnline) _driverRepo.goOffline(session.driverId);
    super.dispose();
  }
}
