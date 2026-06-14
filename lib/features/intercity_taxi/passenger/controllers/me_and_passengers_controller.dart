import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../models/intercity_booking.dart';
import '../../../../models/intercity_ride.dart';
import '../../../../repositories/intercity_bookings_repository.dart';

enum PanelMode { hidden, passengerPick, preview, active }

class MeAndPassengersController extends ChangeNotifier {
  MeAndPassengersController({
    required IntercityBookingsRepository repo,
    required String userPhone,
  })  : _repo = repo,
        _userPhone = userPhone {
    draggableController.addListener(_onSheetExtentChanged);
  }

  VoidCallback? _resetPassengers;

  void attachPassengerReset(VoidCallback resetPassengers) {
    _resetPassengers = resetPassengers;
  }

  final IntercityBookingsRepository _repo;

  String? _userPhone;
  String? _driverId;
  String? _myBookingId;
  List<IntercityBooking> _driverBookings = [];
  IntercityBooking? _myBooking;
  StreamSubscription<List<IntercityBooking>>? _sub;
  Timer? _bookingResolveTimer;
  bool _isLoading = false;
  PanelMode _mode = PanelMode.hidden;
  IntercityRide? _previewRide;
  final DraggableScrollableController draggableController =
      DraggableScrollableController();
  double _sheetExtent = sheetMin;
  String? _pendingPickupBookingId;

  /// Сарлавҳа + «Қўнғироқ/Бекор» тугмалари сигадиган минимал баландлик.
  static const double sheetMin = 0.24;
  static const double sheetMid = 0.45;
  static const double sheetMax = 0.88;
  static const List<double> sheetSnaps = [sheetMin, sheetMid, sheetMax];

  double get sheetExtent => _sheetExtent;
  bool get isSheetCollapsed => _sheetExtent < 0.32;

  bool get isPanelVisible =>
      _mode != PanelMode.hidden || _isLoading;
  bool get isPassengerPick => _mode == PanelMode.passengerPick;
  bool get isPreview => _mode == PanelMode.preview;
  bool get isBookingStep => isPassengerPick || isPreview;
  bool get hasActiveBooking =>
      _mode == PanelMode.active &&
      (_myBooking != null || _myBookingId != null);
  IntercityRide? get previewRide => _previewRide;
  IntercityBooking? get myBooking => _myBooking;
  String? get driverId => _driverId;

  String routeDisplayLabel(Locale locale) {
    if (_previewRide != null) {
      return _previewRide!.routeDisplayLabel(locale);
    }
    final booking = _myBooking;
    if (booking != null) {
      return booking.routeDisplayLabel(locale);
    }
    return '';
  }
  bool get isLoading => _isLoading;

  /// Tasdiqlangan bron, lekin GPS manzili yo'q.
  bool get needsPickup {
    final b = _myBooking;
    if (b == null) return false;
    return b.status == IntercityBookingStatus.confirmed && !b.hasPickupGps;
  }

  bool get shouldOpenPickupSheet =>
      _pendingPickupBookingId != null &&
      _myBooking != null &&
      _myBooking!.id == _pendingPickupBookingId &&
      needsPickup;

  void requestPickupPrompt([String? bookingId]) {
    _pendingPickupBookingId = bookingId ?? _myBookingId;
    notifyListeners();
  }

  void consumePickupPrompt() {
    if (_pendingPickupBookingId == null) return;
    _pendingPickupBookingId = null;
    notifyListeners();
  }

  List<IntercityBooking> get rosterBookings => _driverBookings
      .where(
        (b) =>
            b.id != _myBookingId &&
            (b.status == IntercityBookingStatus.confirmed ||
                b.status == IntercityBookingStatus.pending),
      )
      .toList();

  Future<void> loadIfActive() async {
    if (_userPhone == null || _userPhone!.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        _userPhone = prefs.getString('user_phone') ?? '';
      } catch (e) {
        debugPrint('loadIfActive phone error: $e');
      }
    }
    if (_userPhone == null || _userPhone!.isEmpty) return;
    // Don't reload if already attached
    if (_myBookingId != null ||
        _mode == PanelMode.preview ||
        _mode == PanelMode.passengerPick) {
      return;
    }
    try {
      final snap = await _repo.findActiveBookingForUser(_userPhone!);
      if (snap == null) return;
      attachWithBooking(snap.driverId, snap);
    } catch (e) {
      debugPrint('loadIfActive error: $e');
    }
  }

  void attach(String driverId, String bookingId) {
    _driverId = driverId;
    _myBookingId = bookingId;
    _previewRide = null;
    _mode = PanelMode.active;
    _isLoading = true;
    notifyListeners();
    _startWatch(driverId);
    if (_myBooking == null) {
      _scheduleBookingResolveTimeout();
    }
  }

  void showPassengerPick(IntercityRide ride) {
    if (_myBookingId != null) return;
    _previewRide = ride;
    _mode = PanelMode.passengerPick;
    _sheetExtent = sheetMid;
    notifyListeners();
    _animateSheet(sheetMid, jump: true);
  }

  void confirmPassengerCount() {
    if (_mode != PanelMode.passengerPick || _previewRide == null) return;
    _mode = PanelMode.preview;
    notifyListeners();
  }

  void cancelPassengerPick() {
    if (_mode != PanelMode.passengerPick) return;
    _previewRide = null;
    _mode = PanelMode.hidden;
    _resetPassengers?.call();
    notifyListeners();
  }

  void backToPassengerPick() {
    if (_mode != PanelMode.preview) return;
    _mode = PanelMode.passengerPick;
    notifyListeners();
  }

  void showPreview(IntercityRide ride) {
    if (_myBookingId != null) return;
    _previewRide = ride;
    _mode = PanelMode.preview;
    _sheetExtent = sheetMid;
    notifyListeners();
    _animateSheet(sheetMid, jump: true);
  }

  void cancelPreview() {
    if (_mode != PanelMode.preview) return;
    _previewRide = null;
    _mode = PanelMode.hidden;
    _resetPassengers?.call();
    notifyListeners();
  }

  void attachWithBooking(String driverId, IntercityBooking booking) {
    _driverId = driverId;
    _myBookingId = booking.id;
    _myBooking = booking;
    _previewRide = null;
    _mode = PanelMode.active;
    _isLoading = false;
    _sheetExtent = sheetMin;
    notifyListeners();
    _startWatch(driverId);
    _animateSheet(sheetMin, jump: true);
  }

  void toggleSheetExpanded() {
    if (_mode != PanelMode.active) return;
    final target = isSheetCollapsed ? sheetMid : sheetMin;
    _animateSheet(target);
  }

  void dragSheetBy(double deltaFraction) {
    if (!draggableController.isAttached) return;
    try {
      final next = (draggableController.size + deltaFraction)
          .clamp(sheetMin, sheetMax);
      draggableController.jumpTo(next);
    } catch (e) {
      debugPrint('dragSheetBy error: $e');
    }
  }

  void snapSheetToNearest() {
    if (!draggableController.isAttached) return;
    final size = draggableController.size;
    var nearest = sheetSnaps.first;
    var minDist = (size - nearest).abs();
    for (final snap in sheetSnaps.skip(1)) {
      final dist = (size - snap).abs();
      if (dist < minDist) {
        minDist = dist;
        nearest = snap;
      }
    }
    _animateSheet(nearest);
  }

  void _onSheetExtentChanged() {
    if (!draggableController.isAttached) return;
    final next = draggableController.size;
    if ((next - _sheetExtent).abs() < 0.01) return;
    _sheetExtent = next;
    notifyListeners();
  }

  void _animateSheet(double size, {bool jump = false, int attemptsLeft = 8}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (draggableController.isAttached) {
          if (jump || attemptsLeft <= 2) {
            draggableController.jumpTo(size);
          } else {
            draggableController.animateTo(
              size,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
            );
          }
          return;
        }
      } catch (e) {
        debugPrint('_animateSheet error: $e');
      }
      if (attemptsLeft > 0) {
        _animateSheet(size, jump: jump, attemptsLeft: attemptsLeft - 1);
      }
    });
  }

  void _startWatch(String driverId) {
    _sub?.cancel();
    _bookingResolveTimer?.cancel();
    _sub = _repo.watchByDriver(driverId).listen(
      (list) {
        _driverBookings = list;
        final found = list.firstWhereOrNull((b) => b.id == _myBookingId);
        if (found != null) {
          _myBooking = found;
          _isLoading = false;
          _bookingResolveTimer?.cancel();
        } else if (_myBookingId != null) {
          if (_myBooking == null) {
            _scheduleBookingResolveTimeout();
          }
        } else {
          _isLoading = false;
        }
        notifyListeners();

        if (_myBooking != null &&
            (_myBooking!.status == IntercityBookingStatus.cancelled ||
                _myBooking!.status == IntercityBookingStatus.expired)) {
          detach();
        }
      },
      onError: (e) {
        debugPrint('_startWatch error: $e');
        detach();
      },
    );
  }

  void _scheduleBookingResolveTimeout() {
    _bookingResolveTimer?.cancel();
    if (_myBookingId == null || _myBooking != null) return;
    _bookingResolveTimer = Timer(const Duration(seconds: 8), () {
      unawaited(_resolveBookingById());
    });
  }

  Future<void> _resolveBookingById() async {
    final id = _myBookingId;
    if (id == null || _myBooking != null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('intercity_bookings')
          .doc(id)
          .get();
      if (_myBookingId != id) return;
      if (!doc.exists) {
        detach();
        return;
      }
      final booking = IntercityBooking.fromDoc(doc);
      if (_myBookingId != id) return;
      _myBooking = booking;
      _isLoading = false;
      _bookingResolveTimer?.cancel();
      notifyListeners();
      if (booking.status == IntercityBookingStatus.cancelled ||
          booking.status == IntercityBookingStatus.expired) {
        detach();
      }
    } catch (e) {
      debugPrint('_resolveBookingById error: $e');
    }
  }

  void detach() {
    _bookingResolveTimer?.cancel();
    _bookingResolveTimer = null;
    _sub?.cancel();
    _sub = null;
    _driverId = null;
    _myBookingId = null;
    _myBooking = null;
    _previewRide = null;
    _mode = PanelMode.hidden;
    _driverBookings = [];
    _isLoading = false;
    notifyListeners();
  }

  void collapseForSearch() {
    if (_mode != PanelMode.active) return;
    _animateSheet(sheetMin);
  }

  @override
  void dispose() {
    _bookingResolveTimer?.cancel();
    draggableController.removeListener(_onSheetExtentChanged);
    draggableController.dispose();
    _sub?.cancel();
    super.dispose();
  }
}

extension _ListExt<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
