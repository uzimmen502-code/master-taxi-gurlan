import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../models/active_trip.dart';
import '../../../../models/marshrut_driver_option.dart';
import '../../../../models/schedule.dart';
import '../../../../repositories/rides_repository.dart';
import '../../../../repositories/schedules_repository.dart';

/// Marshrut taksi qidirilayotgan paytdagi state mashinasini boshqaradi:
/// haydovchilarni navbat bilan chaqirib chiqadi, har biri uchun [_timeoutSec]
/// kutadi va trip status'ini real-time eshitadi.
///
/// Ghost protection: 3 marta bekor qilish — 30 daqiqa blok
/// (`users/{phone}/marshrut_block/state`, Firestore).
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

  // ─── Internal ───────────────────────────────────────────────────────
  Timer? _timer;
  StreamSubscription<ActiveTrip>? _tripSub;
  bool _disposed = false;

  // ─── Lifecycle ──────────────────────────────────────────────────────

  Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    _userPhone = prefs.getString('user_phone') ?? '';
    _userAddr = prefs.getString('user_address') ?? '';
    if (_userPhone.isEmpty) {
      _missingPhoneError = 'Профилдан телефон рақамини киритинг';
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
      _moveToNext('Жадвал топилмади');
      return;
    }
    if (sched.seatsLeft <= 0) {
      _moveToNext('Бу ҳайдовчида ўрин қолмаган');
      return;
    }
    if (!sched.routeAllows(pickupMfy, dropoffMfy)) {
      _moveToNext('Йўналиш тўғри келмади');
      return;
    }

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
          ? 'Сизда аллақачон актив маршрут такси сўрови бор'
          : 'Хатолик: ${e.message}';
      _safeNotify();
      return;
    } catch (e) {
      _errorMessage = 'Хатолик: $e';
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
      _moveToNext('Ҳайдовчи рад этди');
    } else if (trip.isNoSeats) {
      _timer?.cancel();
      _moveToNext('Бу ҳайдовчида ўрин қолмаган');
    }
  }

  Future<void> _onTimeout() async {
    final id = _activeTripId;
    if (id != null) {
      try {
        await _rides.markExpired(id);
      } catch (_) {}
    }
    _moveToNext('Ҳайдовчи жавоб бермади');
  }

  void _moveToNext(String reason) {
    if (_disposed) return;
    _tripSub?.cancel();
    _skipReason = reason;
    _safeNotify();
    Future.delayed(const Duration(milliseconds: 800), () {
      if (_disposed) return;
      _sendToDriver(_currentIndex + 1);
    });
  }

  /// Foydalanuvchi "БЕКОР ҚИЛИШ" tugmasini bosganda.
  /// Ghost protection: 3 ta cancel — 30 daqiqa blok (Firestore).
  Future<void> cancelByUser() async {
    final id = _activeTripId;
    if (id != null) {
      try {
        await _rides.markCancelled(id);
      } catch (_) {}
    }

    if (_userPhone.isEmpty) return;
    final uid = phoneDigits(_userPhone);
    if (uid.isEmpty) return;

    try {
      final blockRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('marshrut_block')
          .doc('state');

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(blockRef);
        final count = (snap.data()?['cancelCount'] as num?)?.toInt() ?? 0;
        final newCount = count + 1;

        if (newCount >= 3) {
          tx.set(blockRef, {
            'cancelCount': 0,
            'blockedUntil': Timestamp.fromDate(
              DateTime.now().add(const Duration(minutes: 30)),
            ),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          tx.set(blockRef, {
            'cancelCount': newCount,
            'blockedUntil': null,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (_) {
      // Firestore xatosi — davom etamiz
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
