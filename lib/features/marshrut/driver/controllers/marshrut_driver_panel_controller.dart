import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;
import 'package:geolocator/geolocator.dart';

import '../../../../models/active_trip.dart';
import '../../../../repositories/marshrut_driver_repository.dart';
import '../../../../repositories/rides_repository.dart';
import '../../../../repositories/schedules_repository.dart';
import '../../../../services/notification_service.dart';

/// Marshrut haydovchi panelining state mashinasi.
///
/// Mas'uliyatlari:
/// - Bugungi schedule'ni tekshirish va seatsLeft/direction'ni saqlash
/// - Online toggle (GPS + Firestore + heartbeat har 30s + connectivity)
/// - `trips` real-time stream'i: pending'larни ko'rsatish, янги kelganda
///   dialog uchun trigger qo'ymaslik (dialog uchun `pendingDialogTripId`)
/// - Accept/reject (RidesRepository atomic'ы chaqiriladi)
/// - App resume'da pending tekshiruvi
class MarshrutDriverPanelController extends ChangeNotifier {
  MarshrutDriverPanelController({
    required this.driverId,
    required this.driverName,
    required this.driverPhone,
    required this.carModel,
    required this.plate,
    required this.seats,
    required List<String> initialStops,
    required MarshrutDriverRepository marshrutRepo,
    required SchedulesRepository schedulesRepo,
    required RidesRepository ridesRepo,
    NotificationService? notifications,
  })  : _marshrut = marshrutRepo,
        _schedules = schedulesRepo,
        _rides = ridesRepo,
        _notifications = notifications ?? NotificationService.instance,
        _stops = List<String>.from(initialStops);

  final String driverId;
  final String driverName;
  final String driverPhone;
  final String carModel;
  final String plate;
  final int seats;

  final MarshrutDriverRepository _marshrut;
  final SchedulesRepository _schedules;
  final RidesRepository _rides;
  final NotificationService _notifications;

  // ─── State ──────────────────────────────────────────────────────────
  bool _isOnline = false;
  bool _hasScheduleToday = false;
  int _seatsLeft = 0;
  int _seatsTotal = 0;
  String _direction = 'forward';
  List<String> _stops;
  String? _scheduleId;
  List<ActiveTrip> _requests = const [];
  List<ActiveTrip> _acceptedTrips = const [];
  int _queuePosition = 0;
  String? _autoPausedReason;
  String? _errorMessage;
  String? _info;
  String? _pendingDialogTripId;

  bool get isOnline => _isOnline;
  bool get hasScheduleToday => _hasScheduleToday;
  int get seatsLeft => _seatsLeft;
  int get seatsTotal => _seatsTotal;
  String get direction => _direction;
  List<String> get stops => List.unmodifiable(_stops);
  String? get scheduleId => _scheduleId;
  List<ActiveTrip> get requests => List.unmodifiable(_requests);
  List<ActiveTrip> get acceptedTrips => List.unmodifiable(_acceptedTrips);
  int get queuePosition => _queuePosition;
  String? get autoPausedReason => _autoPausedReason;
  bool get isAutoPaused => _autoPausedReason != null;
  String? get errorMessage => _errorMessage;
  String? get info => _info;
  String? get pendingDialogTripId => _pendingDialogTripId;
  bool get hasRequests => _requests.isNotEmpty;
  bool get hasAcceptedTrips => _acceptedTrips.isNotEmpty;

  ActiveTrip? rideById(String id) {
    for (final r in _requests) {
      if (r.id == id) return r;
    }
    return null;
  }

  // ─── Internals ──────────────────────────────────────────────────────
  StreamSubscription<List<ActiveTrip>>? _tripsSub;
  StreamSubscription<List<ActiveTrip>>? _acceptedTripsSub;
  StreamSubscription<int>? _queueSub;
  StreamSubscription<String?>? _pauseSub;
  StreamSubscription<List<ConnectivityResult>>? _connectSub;
  Timer? _heartbeatTimer;
  bool _disposed = false;

  String get _todayDateStr {
    final d = DateTime.now();
    return '${d.year}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  // ─── Lifecycle ──────────────────────────────────────────────────────

  Future<void> init() async {
    _notifications.setOnTapped(checkPendingTrips);
    if (!kIsWeb) await _notifications.setup();
    await checkTodaySchedule();
  }

  @override
  void dispose() {
    _disposed = true;
    _notifications.setOnTapped(null);
    _tripsSub?.cancel();
    _acceptedTripsSub?.cancel();
    _queueSub?.cancel();
    _pauseSub?.cancel();
    _connectSub?.cancel();
    _heartbeatTimer?.cancel();
    if (_isOnline) {
      // Best-effort offline'ni yutamiz — fire-and-forget
      _marshrut.goOffline(driverId).catchError((_) {});
    }
    super.dispose();
  }

  void clearTransient() {
    _errorMessage = null;
    _info = null;
    _safeNotify();
  }

  /// UI'da dialog ko'rsatildi/yopildi — controller marker'ni tozalaydi.
  void dialogShown() {
    _pendingDialogTripId = null;
    _safeNotify();
  }

  // ─── Schedule ───────────────────────────────────────────────────────

  Future<void> checkTodaySchedule() async {
    try {
      final s = await _schedules.getTodayActiveForDriver(
        driverId: driverId,
        date: _todayDateStr,
      );
      if (_disposed) return;
      if (s != null) {
        _hasScheduleToday = true;
        _scheduleId = s.id;
        _seatsLeft = s.seatsLeft;
        _seatsTotal = seats;
        _direction = s.direction;
        if (s.stops.isNotEmpty) _stops = List<String>.from(s.stops);
        _listenAutoPause();
      } else {
        _hasScheduleToday = false;
      }
      _safeNotify();
    } catch (_) {
      // Tekshiruvda xato — bayroqlar o'z holatida qoladi
    }
  }

  // ─── Online toggle ──────────────────────────────────────────────────

  Future<void> goOnline() async {
    try {
      double? lat;
      double? lng;
      if (!kIsWeb) {
        try {
          var perm = await Geolocator.checkPermission();
          if (perm == LocationPermission.denied) {
            perm = await Geolocator.requestPermission();
          }
          if (perm != LocationPermission.denied &&
              perm != LocationPermission.deniedForever) {
            final pos = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
              timeLimit: const Duration(seconds: 8),
            );
            lat = pos.latitude;
            lng = pos.longitude;
          }
        } catch (_) {
          // GPS xatosida ham onlайн bo'lishni davom ettiramiz
        }
      }

      await _marshrut.goOnline(
        uid: driverId,
        lat: lat,
        lng: lng,
        scheduleId: _scheduleId,
      );
      if (_disposed) return;
      _isOnline = true;
      _info = '🟢 Онлайн';
      _safeNotify();

      _listenTrips();
      _listenQueue();
      _listenAutoPause();
      _startHeartbeat();
      _listenConnectivity();
    } catch (e) {
      _errorMessage = 'Хатолик: $e';
      _safeNotify();
    }
  }

  Future<void> goOffline() async {
    if (_acceptedTrips.isNotEmpty) {
      _errorMessage = '❗ Аввал қабул қилинган сафарни якунланг';
      _safeNotify();
      return;
    }
    _heartbeatTimer?.cancel();
    await _connectSub?.cancel();
    _connectSub = null;
    try {
      await _marshrut.goOffline(driverId);
    } catch (_) {}
    await _tripsSub?.cancel();
    await _acceptedTripsSub?.cancel();
    await _queueSub?.cancel();
    await _pauseSub?.cancel();
    _tripsSub = null;
    _acceptedTripsSub = null;
    _queueSub = null;
    _pauseSub = null;
    if (_disposed) return;
    _isOnline = false;
    _requests = const [];
    _acceptedTrips = const [];
    _safeNotify();
  }

  void _listenTrips() {
    _tripsSub?.cancel();
    _tripsSub = _rides
        .watchPendingForDriver(driverId, taxiType: 'marshrut')
        .listen((list) {
      if (_disposed) return;
      _requests = list;
      if (list.isNotEmpty) {
        final first = list.first;
        if (_pendingDialogTripId != first.id) {
          _pendingDialogTripId = first.id;
          // Bildirishnoma — UI ko'rsatadi yoki forecstda foyda beradi
          if (!kIsWeb) {
            _notifications.showIncomingMarshrutRide(
              pickupMfy: first.pickupMfy,
              dropoffMfy: first.dropoffMfy,
            );
          }
        }
      }
      _safeNotify();
    });

    _acceptedTripsSub?.cancel();
    _acceptedTripsSub = _rides
        .watchAcceptedForDriver(driverId, taxiType: 'marshrut')
        .listen((list) {
      if (_disposed) return;
      _acceptedTrips = list;
      _safeNotify();
    });
  }

  void _listenQueue() {
    _queueSub?.cancel();
    _queueSub =
        _marshrut.watchQueuePosition(myDriverId: driverId).listen((pos) {
      if (_disposed) return;
      _queuePosition = pos;
      _safeNotify();
    });
  }

  void _listenAutoPause() {
    _pauseSub?.cancel();
    _pauseSub = _marshrut.watchAutoPausedReason(driverId).listen((reason) {
      if (_disposed) return;
      _autoPausedReason = reason;
      if (reason != null) {
        _queuePosition = 0;
        _info = '⏸ Навбатдан вақтинча чиқарилдингиз';
      }
      _safeNotify();
    });
  }

  Future<void> reactivateFromAutoPause() async {
    try {
      await _marshrut.reactivateAutoPaused(driverId);
      if (_disposed) return;
      _autoPausedReason = null;
      _info = '✅ Навбатга қайтдингиз';
      _safeNotify();
    } catch (e) {
      _errorMessage = 'Хатолик: $e';
      _safeNotify();
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_isOnline || _disposed) return;
      try {
        await _marshrut.heartbeat(driverId);
      } catch (_) {}
    });
  }

  void _listenConnectivity() {
    _connectSub?.cancel();
    _connectSub = Connectivity().onConnectivityChanged.listen((results) async {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (offline && _isOnline) {
        if (_disposed) return;
        _isOnline = false;
        _info = '📵 Интернет узилди';
        _safeNotify();
      } else if (!offline && !_isOnline && _hasScheduleToday) {
        await goOnline();
        _info = '🟢 Уланиш тикланди';
        _safeNotify();
      }
    });
  }

  // ─── Direction switch ──────────────────────────────────────────────

  Future<void> finishTrip() async {
    if (_requests.isNotEmpty) {
      _errorMessage = '❗ Аввал буюртмаларни ҳал қилинг';
      _safeNotify();
      return;
    }
    if (_acceptedTrips.isNotEmpty) {
      _errorMessage = '❗ Аввал қабул қилинган сафарни якунланг';
      _safeNotify();
      return;
    }
    try {
      final newDir = _direction == 'forward' ? 'backward' : 'forward';
      await _marshrut.switchDirection(
        uid: driverId,
        scheduleId: _scheduleId,
        newDirection: newDir,
        seatsTotal: _seatsTotal,
      );
      if (_disposed) return;
      _direction = newDir;
      _seatsLeft = _seatsTotal;
      _info = '✅ Йўналиш ўзгарди';
      _safeNotify();
    } catch (e) {
      _errorMessage = 'Хатолик: $e';
      _safeNotify();
    }
  }

  // ─── Accept / Reject ───────────────────────────────────────────────

  /// Qabul natijasi — UI uchun. `true` muvaffaqiyatli, `false` — xato yoki
  /// route nomos kelmadi (sabab `errorMessage`'da).
  Future<bool> acceptRide(String tripId) async {
    final ride = rideById(tripId);
    if (ride == null) return false;

    if (!_isValidRoute(ride.pickupMfy, ride.dropoffMfy)) {
      _errorMessage = '❌ Нотўғри маршрут';
      _safeNotify();
      await rejectRide(tripId);
      return false;
    }

    try {
      final ok = await _rides.acceptMarshrutRide(
        tripId: tripId,
        scheduleId: _scheduleId,
        driverId: driverId,
        driverName: driverName,
        driverPhone: driverPhone,
        driverCar: carModel,
        driverPlate: plate,
      );
      if (_disposed) return false;
      if (!ok) {
        _errorMessage = '🚫 Бўш жой йўқ ёки буюртма яроқсиз';
        _safeNotify();
        return false;
      }
      _seatsLeft = (_seatsLeft - 1).clamp(0, _seatsTotal);
      _requests = _requests.where((r) => r.id != tripId).toList();
      _info = '✅ Қабул қилинди';
      _safeNotify();
      return true;
    } catch (e) {
      _errorMessage = 'Хатолик: $e';
      _safeNotify();
      return false;
    }
  }

  Future<void> rejectRide(String tripId) async {
    try {
      await _rides.rejectRide(tripId: tripId, driverId: driverId);
    } catch (_) {}
  }

  Future<void> completeRide(String tripId) async {
    try {
      await _rides.completeMarshrutRide(
        tripId: tripId,
        driverId: driverId,
      );
      if (_disposed) return;
      _acceptedTrips = _acceptedTrips.where((r) => r.id != tripId).toList();
      _info = '✅ Сафар якунланди';
      _safeNotify();
    } catch (e) {
      _errorMessage = 'Хатолик: $e';
      _safeNotify();
    }
  }

  bool _isValidRoute(String from, String to) {
    final fromIdx = _stops.indexOf(from);
    final toIdx = _stops.indexOf(to);
    if (fromIdx == -1 || toIdx == -1) return false;
    return _direction == 'forward' ? fromIdx < toIdx : fromIdx > toIdx;
  }

  // ─── App lifecycle (screen forwards) ───────────────────────────────

  Future<void> checkPendingTrips() async {
    if (!_isOnline || _disposed) return;
    try {
      final list =
          await _rides.getPendingForDriver(driverId, taxiType: 'marshrut');
      if (_disposed || list.isEmpty) return;
      final first = list.first;
      if (_pendingDialogTripId != first.id) {
        _requests = list;
        _pendingDialogTripId = first.id;
        _safeNotify();
      }
    } catch (_) {}
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }
}
