import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier, VoidCallback, debugPrint, kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../models/active_trip.dart';
import '../../../../services/location_service.dart';
import '../../../../models/schedule.dart';
import '../../../../repositories/marshrut_driver_repository.dart';
import '../../../../repositories/rides_repository.dart';
import '../../../../repositories/schedules_repository.dart';
import '../../../../repositories/user_repository.dart';
import '../../../../services/balance_service.dart';
import '../../../../services/deferred_settlement_queue.dart';
import '../../../../services/notification_service.dart';
import '../../../../services/settlement_service.dart';
import '../../../../utils/gurlan_places.dart';

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
    required String driverId,
    required this.driverName,
    required this.driverPhone,
    required String carModel,
    required String plate,
    required int seats,
    required List<String> initialStops,
    required MarshrutDriverRepository marshrutRepo,
    required SchedulesRepository schedulesRepo,
    required RidesRepository ridesRepo,
    NotificationService? notifications,
  })  : driverId = canonicalPhoneId(driverId),
        _marshrut = marshrutRepo,
        _schedules = schedulesRepo,
        _rides = ridesRepo,
        _notifications = notifications ?? NotificationService.instance,
        _stops = List<String>.from(initialStops),
        _carModel = carModel,
        _plate = plate,
        _profileSeats = seats;

  final String driverId;
  final String driverName;
  final String driverPhone;
  String _carModel;
  String _plate;
  int _profileSeats;

  String get carModel => _carModel;
  String get plate => _plate;
  int get seats => _profileSeats;

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
  bool isDialogOpen = false;
  VoidCallback? onStopRingtone;
  VoidCallback? onEndStopApproaching;
  void Function(String tripId)? onPassengerOrderCancelled;

  LatLng? _endStopCoords;
  bool _endStopDialogShown = false;
  bool _endStopDialogActive = false;
  double? _currentLat;
  double? _currentLng;

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
  bool _initDone = false;
  bool get initDone => _initDone;

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
  StreamSubscription<Schedule?>? _scheduleSub;
  Timer? _heartbeatTimer;
  Timer? _reachabilityTimer;
  bool _disposed = false;
  bool _offlineDueToNetwork = false;
  bool _pendingServerOffline = false;
  static const Duration _reachabilityProbeInterval = Duration(seconds: 5);
  static const Duration _serverReachabilityTimeout = Duration(seconds: 3);

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
    await refreshProfileInfo();
    await checkTodaySchedule();
    await _restoreOnlineState();
    _initDone = true;
    _safeNotify();
  }

  Future<void> _restoreOnlineState() async {
    try {
      if (!await _hasNetworkInterface()) return;
      final snap = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(driverId)
          .get(const GetOptions(source: Source.server));
      if (!snap.exists || _disposed) return;
      final isOnline = snap.data()?['isOnline'] as bool? ?? false;
      if (isOnline) {
        _isOnline = true;
        _listenTrips();
        _listenQueue();
        _listenAutoPause();
        _listenConnectivity();
        _startHeartbeat();
        _startReachabilityProbe();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('restoreOnlineState error: $e');
    }
  }

  Future<bool> _hasNetworkInterface() async {
    if (kIsWeb) return true;
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  Future<bool> _canReachFirestoreServer() async {
    try {
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(driverId)
          .get(const GetOptions(source: Source.server))
          .timeout(_serverReachabilityTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// App resume yoki connectivity o'zgarishida — darhol tekshirish.
  Future<void> probeNetworkNow() => _probeNetworkAndMaybeOffline();

  Future<void> _probeNetworkAndMaybeOffline() async {
    if (!_isOnline || _disposed) return;
    if (!await _hasNetworkInterface()) {
      await _goOfflineForNetworkLoss();
      return;
    }
    if (!await _canReachFirestoreServer()) {
      await _goOfflineForNetworkLoss();
    }
  }

  Future<void> _goOfflineForNetworkLoss() async {
    if (!_isOnline || _disposed) return;
    _offlineDueToNetwork = true;
    await _applyOffline(
      cancelConnectivityListener: false,
      infoMessage: 'internet_disconnected_offline',
    );
  }

  void _startReachabilityProbe() {
    _reachabilityTimer?.cancel();
    if (kIsWeb) return;
    unawaited(_probeNetworkAndMaybeOffline());
    _reachabilityTimer = Timer.periodic(
      _reachabilityProbeInterval,
      (_) => unawaited(_probeNetworkAndMaybeOffline()),
    );
  }

  void _stopReachabilityProbe() {
    _reachabilityTimer?.cancel();
    _reachabilityTimer = null;
  }

  Future<void> refreshProfileInfo() async {
    try {
      var model = _carModel;
      var plate = _plate;
      var seats = _profileSeats;
      var userSeats = 0;

      final carInfo = await UserRepository().getCarInfo(driverId);
      if (!_disposed && carInfo != null) {
        final userModel = (carInfo['carModel'] ?? '').trim();
        final userPlate = (carInfo['carPlate'] ?? '').trim();
        userSeats = int.tryParse(carInfo['carSeats'] ?? '') ?? 0;
        if (userModel.isNotEmpty) model = userModel;
        if (userPlate.isNotEmpty) plate = userPlate.toUpperCase();
        if (userSeats > 0) seats = userSeats;
      }

      final profile = await _marshrut.getProfile(driverId);
      if (_disposed) return;
      if (profile != null && profile.stops.isNotEmpty) {
        _stops = List<String>.from(profile.stops);
      }

      final scheduleSeatsMismatch =
          userSeats > 0 && _hasScheduleToday && _seatsTotal != userSeats;
      final changed = model.trim() != _carModel.trim() ||
          plate.trim().toUpperCase() != _plate.trim().toUpperCase() ||
          (seats > 0 && seats != _profileSeats) ||
          scheduleSeatsMismatch;

      if (model.trim().isNotEmpty) _carModel = model.trim();
      if (plate.trim().isNotEmpty) _plate = plate.trim().toUpperCase();
      if (seats > 0) _profileSeats = seats;

      if (changed &&
          _carModel.isNotEmpty &&
          _plate.isNotEmpty &&
          _profileSeats > 0) {
        await _marshrut.syncCarFields(
          uid: driverId,
          carModel: _carModel,
          plate: _plate,
          seats: _profileSeats,
          activeScheduleId: _scheduleId,
        );
        if (_hasScheduleToday && _scheduleId != null) {
          final sched = await _schedules.getTodayActiveForDriver(
            driverId: driverId,
            date: _todayDateStr,
          );
          if (!_disposed && sched != null) {
            _seatsLeft = sched.seatsLeft;
            _seatsTotal = sched.seats;
          }
        }
      }

      _safeNotify();
    } catch (e) {
      debugPrint('refreshProfileInfo error: $e');
    }
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
    _scheduleSub?.cancel();
    _heartbeatTimer?.cancel();
    _stopReachabilityProbe();
    // Panel close ≠ go offline.
    // goOffline() only via: toggle, forceLeave,
    // app terminate (marshrutDriverAutoOffline CF)
    super.dispose();
  }

  void clearTransient() {
    _errorMessage = null;
    _info = null;
    _safeNotify();
  }

  void clearError() => clearTransient();

  /// Push / deep link: dialog uchun tripId (pending ro'yxatni yangilaydi).
  Future<void> setPendingDialogTripId(String tripId) async {
    if (tripId.isEmpty || _disposed) return;
    _pendingDialogTripId = tripId;
    try {
      final list =
          await _rides.getPendingForDriver(driverId, taxiType: 'marshrut');
      if (!_disposed) {
        _requests = list;
      }
    } catch (e) {
      debugPrint('setPendingDialogTripId: $e');
    }
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
      await refreshProfileInfo();
      final s = await _schedules.getTodayActiveForDriver(
        driverId: driverId,
        date: _todayDateStr,
      );
      if (_disposed) return;
      if (s != null) {
        _hasScheduleToday = true;
        _scheduleId = s.id;
        _seatsLeft = s.seatsLeft;
        _seatsTotal = s.seats;
        _direction = s.direction;
        if (s.stops.isNotEmpty) _stops = List<String>.from(s.stops);
        _listenAutoPause();
        _listenSchedule();
      } else {
        _hasScheduleToday = false;
        _scheduleSub?.cancel();
        _errorMessage = 'no_schedule_today';
      }
      _safeNotify();
    } catch (e) {
      _errorMessage = 'schedule_load_failed';
      debugPrint('checkTodaySchedule error: $e');
      _safeNotify();
    }
  }

  // ─── Online toggle ──────────────────────────────────────────────────

  Future<void> goOnline() async {
    try {
      double? lat;
      double? lng;
      if (!kIsWeb) {
        try {
          final coords = await const LocationService().getCurrentCoords(
            mediumTimeout: const Duration(seconds: 4),
            highTimeout: const Duration(seconds: 6),
          );
          lat = coords.lat;
          lng = coords.lng;
          _currentLat = lat;
          _currentLng = lng;
        } on LocationException catch (e) {
          _errorMessage = switch (e.kind) {
            LocationErrorKind.permissionDenied => 'gps_permission_denied_msg',
            LocationErrorKind.serviceDisabled => 'gps_service_disabled_msg',
            LocationErrorKind.timeout => 'gps_timeout_msg',
            LocationErrorKind.lookupFailed => 'gps_lookup_failed_msg',
          };
          _safeNotify();
          return;
        } catch (_) {
          _errorMessage = 'gps_unavailable';
          _safeNotify();
          return;
        }
      }

      await _marshrut.goOnline(
        uid: driverId,
        lat: lat,
        lng: lng,
        scheduleId: _scheduleId,
      );
      if (_disposed) return;
      if (!kIsWeb && !await _canReachFirestoreServer()) {
        try {
          await _marshrut.goOffline(driverId, scheduleId: _scheduleId);
        } catch (_) {}
        _errorMessage = 'internet_disconnected_offline';
        _safeNotify();
        return;
      }
      _isOnline = true;
      _offlineDueToNetwork = false;
      _info = 'online';
      _safeNotify();

      _listenTrips();
      _listenQueue();
      _listenAutoPause();
      _startHeartbeat();
      _listenConnectivity();
      _startReachabilityProbe();
      await _loadEndStopCoords();
    } catch (e) {
      _errorMessage = 'error_generic|$e';
      _safeNotify();
    }
  }

  void markEndStopDialogClosed() {
    _endStopDialogActive = false;
  }

  Future<void> _loadEndStopCoords() async {
    if (_stops.length < 2) return;
    final from = _stops.first;
    final to = _stops.last;
    final targetFrom = _direction == 'forward' ? from : to;
    final targetTo = _direction == 'forward' ? to : from;

    var coords = await _marshrut.getRouteCoordinates(targetFrom, targetTo);
    var reversed = false;
    if (coords == null) {
      coords = await _marshrut.getRouteCoordinates(targetTo, targetFrom);
      reversed = true;
    }
    if (coords == null || _disposed) return;

    final num endLat;
    final num endLng;
    if (reversed) {
      endLat = _direction == 'forward' ? coords['startLat']! : coords['endLat']!;
      endLng = _direction == 'forward' ? coords['startLng']! : coords['endLng']!;
    } else {
      endLat = _direction == 'forward' ? coords['endLat']! : coords['startLat']!;
      endLng = _direction == 'forward' ? coords['endLng']! : coords['startLng']!;
    }
    _endStopCoords = LatLng(endLat.toDouble(), endLng.toDouble());
  }

  Future<void> _finishAllAcceptedTrips() async {
    final trips = List<ActiveTrip>.from(_acceptedTrips);
    for (final trip in trips) {
      if (trip.id.isEmpty) continue;
      try {
        await _rides.completeMarshrutRide(tripId: trip.id, driverId: driverId);
      } catch (e) {
        debugPrint('marshrut complete ${trip.id}: $e');
      }
    }
    if (_disposed) return;
    _acceptedTrips = const [];
    _safeNotify();
  }

  Future<void> goOffline({bool force = false}) async {
    if (!force && _acceptedTrips.isNotEmpty) {
      _errorMessage = 'finish_accepted_trip_first';
      _safeNotify();
      return;
    }
    _offlineDueToNetwork = false;
    await _applyOffline(cancelConnectivityListener: true);
  }

  Future<void> _applyOffline({
    required bool cancelConnectivityListener,
    String? infoMessage,
  }) async {
    final wasOnline = _isOnline;
    _heartbeatTimer?.cancel();
    _stopReachabilityProbe();

    // UI darhol offline — server javobini kutmaymiz.
    _isOnline = false;
    _requests = const [];
    _acceptedTrips = const [];
    _endStopDialogShown = false;
    _endStopDialogActive = false;
    _endStopCoords = null;
    _currentLat = null;
    _currentLng = null;
    if (infoMessage != null) _info = infoMessage;
    _safeNotify();

    if (cancelConnectivityListener) {
      await _connectSub?.cancel();
      _connectSub = null;
    }
    await _tripsSub?.cancel();
    await _acceptedTripsSub?.cancel();
    await _queueSub?.cancel();
    await _pauseSub?.cancel();
    _tripsSub = null;
    _acceptedTripsSub = null;
    _queueSub = null;
    _pauseSub = null;
    if (_disposed) return;

    if (wasOnline) {
      unawaited(_syncOfflineToServer());
    }
  }

  Future<void> _syncOfflineToServer() async {
    try {
      await _marshrut
          .goOffline(driverId, scheduleId: _scheduleId)
          .timeout(_serverReachabilityTimeout);
      _pendingServerOffline = false;
    } catch (_) {
      _pendingServerOffline = true;
    }
  }

  Future<bool> _flushPendingServerOffline() async {
    if (!_pendingServerOffline || _disposed) return true;
    if (!await _hasNetworkInterface()) return false;
    if (!await _canReachFirestoreServer()) return false;
    try {
      await _marshrut
          .goOffline(driverId, scheduleId: _scheduleId)
          .timeout(_serverReachabilityTimeout);
      _pendingServerOffline = false;
      return true;
    } catch (_) {
      return false;
    }
  }

  void _listenTrips() {
    _tripsSub?.cancel();
    _tripsSub = _rides
        .watchPendingForDriver(driverId, taxiType: 'marshrut')
        .listen((list) {
      if (_disposed) return;
      _requests = list;
      if (_pendingDialogTripId != null &&
          !_requests.any((r) => r.id == _pendingDialogTripId)) {
        final removedId = _pendingDialogTripId!;
        _pendingDialogTripId = null;
        onStopRingtone?.call();
        unawaited(_notifyPassengerCancelIfNeeded(removedId));
        notifyListeners();
      }
      if (list.isNotEmpty &&
          _pendingDialogTripId == null &&
          !isDialogOpen) {
        final first = list.first;
        _pendingDialogTripId = first.id;
        unawaited(
          _notifications.showIncomingMarshrutRide(
            pickupMfy: first.pickupMfy,
            dropoffMfy: first.dropoffMfy,
          ),
        );
      }
      _safeNotify();
    });

    _acceptedTripsSub?.cancel();
    _acceptedTripsSub = _rides
        .watchAcceptedForDriver(driverId, taxiType: 'marshrut')
        .listen((list) {
      if (_disposed) return;
      final removedIds = _acceptedTrips
          .where((t) => !list.any((n) => n.id == t.id))
          .map((t) => t.id);
      _acceptedTrips = list;
      for (final id in removedIds) {
        unawaited(_notifyPassengerCancelIfNeeded(id));
      }
      _safeNotify();
    });
  }

  Future<void> _notifyPassengerCancelIfNeeded(String tripId) async {
    if (tripId.isEmpty) return;
    try {
      final trip = await _rides.getTrip(tripId);
      if (trip != null && trip.isPassengerCancelled) {
        onPassengerOrderCancelled?.call(tripId);
      }
    } catch (_) {}
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
        _info = 'queue_paused_temporarily';
      }
      _safeNotify();
    });
  }

  Future<void> reactivateFromAutoPause() async {
    try {
      await _marshrut.reactivateAutoPaused(driverId);
      if (_disposed) return;
      _autoPausedReason = null;
      _safeNotify();
    } catch (e) {
      _errorMessage = 'error_generic|$e';
      _safeNotify();
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_isOnline || _disposed) return;
      try {
        double? lat;
        double? lng;
        if (!kIsWeb) {
          try {
            final pos = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.medium,
                timeLimit: Duration(seconds: 6),
              ),
            );
            lat = pos.latitude;
            lng = pos.longitude;
            _currentLat = lat;
            _currentLng = lng;
          } catch (_) {}
        }
        await _marshrut.heartbeat(driverId, lat: lat, lng: lng);

        if (_endStopCoords == null) {
          await _loadEndStopCoords();
        }
        if (_endStopCoords != null &&
            !_endStopDialogShown &&
            !_endStopDialogActive &&
            _currentLat != null &&
            _currentLng != null) {
          final dist = LocationService.distanceKm(
            _currentLat!,
            _currentLng!,
            _endStopCoords!.latitude,
            _endStopCoords!.longitude,
          );
          if (dist <= 1.0) {
            _endStopDialogShown = true;
            _endStopDialogActive = true;
            onEndStopApproaching?.call();
          }
        }
      } catch (_) {}
    });
  }

  void _listenSchedule() {
    _scheduleSub?.cancel();
    final id = _scheduleId;
    if (id == null || id.isEmpty) return;
    _scheduleSub = _schedules.watchById(id).listen((sched) {
      if (_disposed || sched == null) return;
      _seatsLeft = sched.seatsLeft;
      _seatsTotal = sched.seats;
      _direction = sched.direction;
      if (sched.stops.isNotEmpty) _stops = List<String>.from(sched.stops);
      _safeNotify();
    });
  }

  void _listenConnectivity() {
    if (kIsWeb) return;
    _connectSub?.cancel();
    _connectSub =
        Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
    unawaited(_onConnectivityChanged(null));
  }

  Future<void> _onConnectivityChanged(List<ConnectivityResult>? results) async {
    if (_disposed) return;
    final list = results ?? await Connectivity().checkConnectivity();
    final hasInterface = list.any((r) => r != ConnectivityResult.none);

    if (_isOnline) {
      if (!hasInterface) {
        await _goOfflineForNetworkLoss();
        return;
      }
      if (!await _canReachFirestoreServer()) {
        await _goOfflineForNetworkLoss();
      }
      return;
    }

    if (hasInterface &&
        _offlineDueToNetwork &&
        !_isOnline &&
        _hasScheduleToday &&
        !isAutoPaused) {
      if (_pendingServerOffline) {
        final flushed = await _flushPendingServerOffline();
        if (!flushed) return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever) {
        await goOnline();
        if (_isOnline) {
          _info = 'connection_restored';
          _safeNotify();
        }
      }
    }
  }

  // ─── Direction switch ──────────────────────────────────────────────

  Future<void> switchDirection() async {
    if (_requests.isNotEmpty) {
      _errorMessage = 'resolve_orders_first';
      _safeNotify();
      return;
    }
    if (_acceptedTrips.isNotEmpty) {
      _errorMessage = 'finish_accepted_trip_first';
      _safeNotify();
      return;
    }
    await _applyDirectionSwitch();
  }

  /// Охирги бекатга яқинлашганда: accepted рўйхатни якунлаб тозалайди, йўналиш алмашади.
  /// Ҳайдовчи onlayn qoladi va yangi buyurtmalarni qabul qila oladi.
  Future<void> forceEndAndSwitch() async {
    if (_requests.isNotEmpty) {
      _errorMessage = 'resolve_orders_first';
      _safeNotify();
      return;
    }
    _errorMessage = null;
    try {
      await _finishAllAcceptedTrips();
      if (_disposed) return;
      await _applyDirectionSwitch();
    } catch (e) {
      _errorMessage = 'error_generic|$e';
      _safeNotify();
    }
  }

  /// «Йўқ» — accepted tripni yakunlab, oflayn.
  Future<void> forceEndAndGoOffline() async {
    if (_requests.isNotEmpty) {
      _errorMessage = 'resolve_orders_first';
      _safeNotify();
      return;
    }
    _errorMessage = null;
    try {
      await _finishAllAcceptedTrips();
      if (_disposed) return;
      await goOffline(force: true);
    } catch (e) {
      _errorMessage = 'error_generic|$e';
      _safeNotify();
    }
  }

  Future<void> _applyDirectionSwitch() async {
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
      _endStopDialogShown = false;
      _endStopDialogActive = false;
      _endStopCoords = null;
      await _loadEndStopCoords();
      _safeNotify();
    } catch (e) {
      _errorMessage = 'error_generic|$e';
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
      _errorMessage = 'invalid_route';
      _safeNotify();
      return false;
    }

    try {
      final outcome = await _rides.acceptMarshrutRide(
        tripId: tripId,
        scheduleId: _scheduleId,
        driverId: driverId,
        driverName: driverName,
        driverPhone: driverPhone,
        driverCar: carModel,
        driverPlate: plate,
      );
      if (_disposed) return false;
      if (!outcome.ok) {
        if (outcome.code == 'expired') {
          _errorMessage = 'request_expired';
        } else if (outcome.code == 'no_seats') {
          _errorMessage = 'no_seats_available';
        } else {
          _errorMessage = 'order_invalid_or_busy';
        }
        _safeNotify();
        return false;
      }
      _requests = _requests.where((r) => r.id != tripId).toList();
      _info = 'ride_accepted';
      _safeNotify();
      return true;
    } catch (e) {
      _errorMessage = 'error_generic|$e';
      _safeNotify();
      return false;
    }
  }

  Future<void> rejectRide(String tripId) async {
    try {
      await _rides.rejectRide(tripId: tripId, driverId: driverId);
    } on FirebaseException catch (e) {
      _errorMessage = 'reject_failed';
      debugPrint('rejectRide error: ${e.code} ${e.message}');
      _safeNotify();
    } catch (e) {
      _errorMessage = 'reject_failed';
      debugPrint('rejectRide unexpected: $e');
      _safeNotify();
    }
  }

  Future<void> cancelAcceptedNoRoom(String tripId) async {
    try {
      await _rides.cancelMarshrutAcceptedByDriver(
        tripId: tripId,
        driverId: driverId,
        noRoom: true,
      );
      if (_disposed) return;
      _acceptedTrips = _acceptedTrips.where((r) => r.id != tripId).toList();
      _info = 'booking_cancelled_reassign';
      _safeNotify();
    } catch (e) {
      _errorMessage = 'error_generic|$e';
      _safeNotify();
    }
  }

  Future<void> completeRide(String tripId, {int? cashPaid}) async {
    try {
      ActiveTrip? trip;
      for (final t in _acceptedTrips) {
        if (t.id == tripId) {
          trip = t;
          break;
        }
      }
      await _rides.completeMarshrutRide(
        tripId: tripId,
        driverId: driverId,
        cashPaid: cashPaid,
      );
      // Qaytim (ledger) — mahalliy taksi bilan bir xil oqim: cashPaid > fare
      // bo'lsa ortib qolgan summa yo'lovchi hisobiga (settlement) o'tkaziladi.
      if (trip != null && cashPaid != null) {
        await _settleMarshrutChange(trip, cashPaid);
      }
      if (_disposed) return;
      _acceptedTrips = _acceptedTrips.where((r) => r.id != tripId).toList();
      _info = 'trip_completed';
      _safeNotify();
    } catch (e) {
      _errorMessage = 'error_generic|$e';
      _safeNotify();
    }
  }

  /// Qaytim — mahalliy taksi `finishRide` mantig'i: Settlement Ledger orqali
  /// (float yetarli bo'lsa Pending settlement; aks holda creditChange; xato →
  /// deferred navbat). Komissiya yo'q — faqat ortiqcha pul yo'lovchiga qaytadi.
  Future<void> _settleMarshrutChange(ActiveTrip trip, int cashPaid) async {
    final fare = trip.fare;
    if (trip.userPhone.isEmpty || cashPaid <= fare) return;
    final change = cashPaid - fare;
    final opId = 'settle_trip_${trip.id}';
    var settled = false;
    try {
      await SettlementService.openSettlement(
        passengerPhone: canonicalPhoneId(trip.userPhone),
        tripId: trip.id,
        opId: opId,
        totalChange: change,
        cashGiven: 0,
      );
      settled = true;
    } catch (e, st) {
      debugPrint('marshrut openSettlement: $e\n$st');
    }
    var credited = false;
    if (!settled) {
      try {
        await BalanceService.creditChange(
          userPhone: trip.userPhone,
          orderTotal: fare,
          cashPaid: cashPaid,
          refType: 'trip',
          refId: trip.id,
          module: 'marshrut',
          idempotencyKey: 'change_trip_${trip.id}',
          operatorPhone: driverPhone,
        );
        credited = true;
      } catch (e, st) {
        debugPrint('marshrut creditChange: $e\n$st');
      }
    }
    if (!settled && !credited) {
      await DeferredSettlementQueue.enqueue(
        passengerPhone: canonicalPhoneId(trip.userPhone),
        tripId: trip.id,
        opId: opId,
        settlementAmount: change,
      );
    }
  }

  bool _isValidRoute(String pickup, String dropoff) {
    final norm = GurlanPlaces.normalizeMfyName;
    final all = _stops.map(norm).toList();
    final iFrom = all.indexOf(norm(pickup));
    final iTo = all.indexOf(norm(dropoff));
    if (_direction == 'forward') {
      return iFrom >= 0 && iTo >= 0 && iFrom < iTo;
    } else {
      return iFrom >= 0 && iTo >= 0 && iFrom > iTo;
    }
  }

  // ─── App lifecycle (screen forwards) ───────────────────────────────

  Future<void> checkPendingTrips() async {
    if (!_isOnline || _disposed) return;
    try {
      final list =
          await _rides.getPendingForDriver(driverId, taxiType: 'marshrut');
      if (_disposed || list.isEmpty) return;
      if (_pendingDialogTripId == null && !isDialogOpen) {
        _requests = list;
        _pendingDialogTripId = list.first.id;
        _safeNotify();
      }
    } catch (_) {}
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }
}
