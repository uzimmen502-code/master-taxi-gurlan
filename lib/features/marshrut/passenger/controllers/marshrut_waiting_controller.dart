import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/passenger_cancel_block_rules.dart';
import '../../../../models/active_trip.dart';
import '../../../../models/marshrut_driver_option.dart';
import '../../../../models/schedule.dart';
import '../../../../repositories/rides_repository.dart';
import '../../../../repositories/schedules_repository.dart';

/// Marshrut taksi qidirilayotgan paytdagi state mashinasini boshqaradi:
/// haydovchilarni navbat bilan chaqirib chiqadi, har biri uchun [_timeoutSec]
/// kutadi va trip status'ini real-time eshitadi.
///
/// Blok: qabul qilingan safardan keyin bekor (CF `applyMarshhrutCancelBlock`,
/// faqat `before.status === accepted`). Kutish bekorida hisoblanmaydi.
class MarshrutWaitingController extends ChangeNotifier {
  MarshrutWaitingController({
    required RidesRepository ridesRepo,
    required SchedulesRepository schedulesRepo,
    required this.pickupMfy,
    required this.pickupAddr,
    required this.dropoffMfy,
    required this.drivers,
    this.userLat,
    this.userLng,
  })  : _rides = ridesRepo,
        _schedules = schedulesRepo;

  /// CF bilan mos — [PassengerCancelBlockRules].
  static int get cancelLimit => PassengerCancelBlockRules.cancelLimit;
  static int get blockMinutes => PassengerCancelBlockRules.blockMinutes;
  static int get windowMinutes => PassengerCancelBlockRules.windowMinutes;

  static const int _defaultTimeoutSec = 15;

  final RidesRepository _rides;
  final SchedulesRepository _schedules;

  // ─── Input ──────────────────────────────────────────────────────────
  final String pickupMfy;
  final String pickupAddr;
  final String dropoffMfy;
  final List<MarshrutDriverOption> drivers;
  final double? userLat;
  final double? userLng;

  // ─── State ──────────────────────────────────────────────────────────
  int _currentIndex = 0;
  int _timeoutSec = _defaultTimeoutSec;
  int _secondsLeft = _defaultTimeoutSec;
  String _userPhone = '';
  String _userAddr = '';
  String? _activeTripId;
  late final String _dispatchSessionId =
      'md_${DateTime.now().microsecondsSinceEpoch}';
  ActiveTrip? _acceptedTrip;
  bool _allRejected = false;
  String? _missingPhoneError;
  String? _errorMessage;
  String? _skipReason;

  int get currentIndex => _currentIndex;
  int get secondsLeft => _secondsLeft;
  int get totalDrivers => drivers.length;
  MarshrutDriverOption? get currentDriver =>
      _currentIndex < drivers.length ? drivers[_currentIndex] : null;
  ActiveTrip? get acceptedTrip => _acceptedTrip;
  bool get allRejected => _allRejected;
  String? get missingPhoneError => _missingPhoneError;
  String? get errorMessage => _errorMessage;
  String? get skipReason => _skipReason;
  int get timeoutSec => _timeoutSec;

  void Function(int remaining)? onCancelWarning;

  // ─── Internal ───────────────────────────────────────────────────────
  Timer? _timer;
  StreamSubscription<ActiveTrip>? _tripSub;
  bool _disposed = false;

  // ─── Lifecycle ──────────────────────────────────────────────────────

  Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    _userPhone = RidesRepository.normalizeMarshrutPhone(
      prefs.getString('user_phone') ?? '',
    );
    final legacyAddr = prefs.getString('user_address') ?? '';
    _userAddr = pickupAddr.trim().isNotEmpty
        ? pickupAddr.trim()
        : legacyAddr.trim();
    if (_userPhone.isEmpty) {
      _missingPhoneError = 'fill_phone_first';
      _safeNotify();
      return;
    }
    _timeoutSec = await _safe(
          () => _rides.getMarshrutOfferTimeoutSeconds(),
        ) ??
        _defaultTimeoutSec;
    _secondsLeft = _timeoutSec;
    await _sendToDriver(0);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _tripSub?.cancel();
    final id = _activeTripId;
    if (id != null) {
      _rides.closeMarshrutOfferIfPending(id).catchError((_) {});
    }
    super.dispose();
  }

  /// UI dialoglar/snackbar ko'rsatgandan keyin sabab/xatoni tozalash uchun.
  void clearTransient() {
    _errorMessage = null;
    _skipReason = null;
    _safeNotify();
  }

  /// Qabul qilingan trip'ni dialog ko'rsatgach iste'mol qiladi.
  ActiveTrip? consumeAcceptedTrip() {
    final t = _acceptedTrip;
    _acceptedTrip = null;
    return t;
  }

  // ─── Flow ───────────────────────────────────────────────────────────

  Future<void> _sendToDriver(int index) async {
    if (_disposed) return;
    if (index >= drivers.length) {
      _allRejected = true;
      _safeNotify();
      return;
    }

    final driver = drivers[index];

    final Schedule? sched =
        await _safe(() => _schedules.getById(driver.scheduleId));
    if (sched == null) {
      _moveToNext('marshrut_driver_not_active');
      return;
    }
    if (sched.seatsLeft <= 0) {
      _moveToNext('no_seat_on_driver');
      return;
    }
    if (!sched.routeAllows(pickupMfy, dropoffMfy)) {
      _moveToNext('marshrut_skip_direction_mismatch');
      return;
    }

    await _finalizeActiveOffer();

    _currentIndex = index;
    _secondsLeft = _timeoutSec;
    _safeNotify();

    try {
      _activeTripId = await _rides.createMarshrutRequest(
        userPhone: _userPhone,
        pickupMfy: pickupMfy,
        pickupAddr: _userAddr,
        dropoffMfy: dropoffMfy,
        driver: driver,
        userLat: userLat,
        userLng: userLng,
        dispatchAttempt: index + 1,
        dispatchTotal: drivers.length,
        dispatchMode: 'queue',
        dispatchSessionId: _dispatchSessionId,
        ttl: Duration(seconds: _timeoutSec + 3),
        offerTimeoutSeconds: _timeoutSec,
      );
    } on StateError catch (e) {
      _errorMessage = e.message == 'active_marshrut_request_exists'
          ? 'active_marshrut_request_exists'
          : 'error_generic|${e.message}';
      _safeNotify();
      return;
    } catch (e) {
      _errorMessage = 'error_generic|$e';
      _safeNotify();
      return;
    }

    _startTimer();
    _listenTrip();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_disposed) {
        t.cancel();
        return;
      }
      if (_secondsLeft <= 0) {
        t.cancel();
        _onTimeout();
        return;
      }
      _secondsLeft--;
      _safeNotify();
    });
  }

  void _listenTrip() {
    _tripSub?.cancel();
    final tripId = _activeTripId;
    if (tripId == null) return;
    _tripSub = _rides.watch(tripId).listen(_onTripUpdate);
  }

  void _onTripUpdate(ActiveTrip trip) {
    if (_disposed) return;
    if (trip.isAccepted) {
      _timer?.cancel();
      _tripSub?.cancel();
      _acceptedTrip = trip;
      _safeNotify();
    } else if (trip.isRejected) {
      _timer?.cancel();
      _moveToNext('driver_rejected_short');
    } else if (trip.isNoSeats) {
      _timer?.cancel();
      _moveToNext('no_seat_on_driver');
    } else if (trip.isExpired || trip.status == 'expired') {
      _timer?.cancel();
      _moveToNext('driver_no_response');
    }
  }

  Future<void> _onTimeout() async {
    final id = _activeTripId;
    if (id != null) {
      try {
        await _rides.markExpired(id);
      } catch (_) {}
      _activeTripId = null;
    }
    _moveToNext('driver_no_response');
  }

  Future<void> _finalizeActiveOffer() async {
    final id = _activeTripId;
    if (id == null) return;
    _tripSub?.cancel();
    _timer?.cancel();
    _activeTripId = null;
    try {
      await _rides.closeMarshrutOfferIfPending(id);
    } catch (_) {}
  }

  void _moveToNext(String reason) {
    if (_disposed) return;
    _tripSub?.cancel();
    _timer?.cancel();
    _activeTripId = null;
    _skipReason = reason;
    _safeNotify();
    Future.delayed(const Duration(milliseconds: 800), () {
      if (_disposed) return;
      _sendToDriver(_currentIndex + 1);
    });
  }

  /// Foydalanuvchi "БЕКОР ҚИЛИШ" tugmasini bosganda (pending — blok hisobi yo'q).
  Future<void> cancelByUser() async {
    final id = _activeTripId;
    if (id != null) {
      try {
        await _rides.markCancelled(id);
      } catch (_) {}
    }
  }

  /// Qabul qilingan safarni bekor qilish (waiting ekranidan).
  Future<void> cancelAfterAccept(String tripId) async {
    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('marshrutPassengerCancelAfterAccept');
      final result = await callable.call({
        'tripId': tripId,
        'reason': 'passenger_cancel_after_accept',
      });
      final data = result.data;
      if (data is Map) {
        if (data['warning'] == true) {
          final remaining = (data['remaining'] as num?)?.toInt() ?? 2;
          onCancelWarning?.call(remaining);
        }
      }
    } catch (e) {
      debugPrint('cancelAfterAccept error: $e');
      try {
        await _rides.cancelMarshrutByPassenger(
          tripId: tripId,
          reason: 'passenger_cancel_after_accept',
        );
      } catch (e2) {
        debugPrint('cancelAfterAccept fallback error: $e2');
      }
    }
  }

  // ─── Helpers ────────────────────────────────────────────────────────

  Future<T?> _safe<T>(Future<T?> Function() fn) async {
    try {
      return await fn();
    } catch (_) {
      return null;
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }
}
