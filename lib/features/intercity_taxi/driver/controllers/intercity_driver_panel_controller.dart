import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../models/intercity_booking.dart';
import '../../../../models/intercity_pickup_route.dart';
import '../../../../repositories/intercity_bookings_repository.dart';
import '../../../../repositories/intercity_rides_repository.dart';
import '../../../../repositories/schedules_repository.dart';
import '../../../../services/intercity_pickup_route_service.dart';
import '../../intercity_driver_alert_text.dart';
import '../../../../services/notification_delivery.dart';
import '../../../../utils/intercity_places.dart';

class IntercityDriverPanelController extends ChangeNotifier {
  IntercityDriverPanelController({
    required this.driverId,
    required this.driverName,
    required this.driverPhone,
    required this.driverCar,
    required this.driverPlate,
    required IntercityBookingsRepository bookingsRepo,
    required SchedulesRepository schedulesRepo,
    IntercityPickupRouteService? pickupRouteService,
    IntercityRidesRepository? ridesRepo,
  })  : _bookingsRepo = bookingsRepo,
        _schedulesRepo = schedulesRepo,
        _pickupRouteService = pickupRouteService ?? IntercityPickupRouteService(),
        _ridesRepo = ridesRepo ?? IntercityRidesRepository();

  final String driverId;
  final String driverName;
  final String driverPhone;
  final String driverCar;
  final String driverPlate;

  final IntercityBookingsRepository _bookingsRepo;
  final SchedulesRepository _schedulesRepo;
  final IntercityPickupRouteService _pickupRouteService;
  final IntercityRidesRepository _ridesRepo;
  final _db = FirebaseFirestore.instance;

  Map<String, dynamic>? tripData;
  List<IntercityBooking> bookings = const [];
  List<IntercityBooking> pending = const [];
  bool autoAccept = false;
  bool isLoading = true;
  String? errorMessage;
  String? pendingDialogBookingId;
  IntercityPickupRoute? pickupRoute;
  bool isCalculatingRoute = false;
  String? routeError;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _tripSub;
  StreamSubscription<List<IntercityBooking>>? _bookingsSub;
  StreamSubscription<List<IntercityBooking>>? _pendingSub;
  bool _disposed = false;
  String _pickupRouteSignature = '';

  List<IntercityBooking> get confirmedBookings => bookings
      .where((b) => b.status == IntercityBookingStatus.confirmed)
      .toList(growable: false);

  List<IntercityBooking> get pickupEligibleBookings => confirmedBookings
      .where(
        (b) =>
            b.hasPickupGps && b.pickupLat != null && b.pickupLng != null,
      )
      .toList(growable: false);

  bool get canCalculatePickupRoute => pickupEligibleBookings.isNotEmpty;

  bool get allPassengersPickedUp {
    final confirmed = confirmedBookings;
    if (confirmed.isEmpty) return false;
    return confirmed.every((b) => b.pickedUp);
  }

  int get totalSeats =>
      (tripData?['seatCapacity'] as num?)?.toInt() ??
      (tripData?['seats'] as num?)?.toInt() ??
      0;
  int get seatsLeft => (tripData?['seats'] as num?)?.toInt() ?? 0;

  bool get isListed => tripData?['isActive'] == true;
  bool get isOnPanel => tripData?['isOnPanel'] != false;

  Future<void> init({bool includeArchived = false}) async {
    await _schedulesRepo.closeExpiredForDriver(driverId);
    await openPanel();
    autoAccept = await _bookingsRepo.getDriverAutoAccept(driverId);
    _tripSub = _db.collection('intercity_drivers').doc(driverId).snapshots().listen(
      (snap) {
        tripData = snap.data();
        _safeNotify();
      },
    );
    _bookingsSub =
        _bookingsRepo.watchByDriver(driverId, includeArchived: includeArchived)
            .listen((list) {
      bookings = list;
      isLoading = false;
      _maybeInvalidatePickupRoute();
      _safeNotify();
    });
    _pendingSub = _bookingsRepo.watchPendingByDriver(driverId).listen((list) {
      final prevIds = pending.map((b) => b.id).toSet();
      pending = list;
      if (list.isNotEmpty) {
        final newest = list.first;
        if (!prevIds.contains(newest.id)) {
          pendingDialogBookingId = newest.id;
          unawaited(
            NotificationDelivery.show(
              title: '🔔 Янги брон сўрови!',
              body: intercityDriverBookingAlertBody(
                userName: newest.userName,
                routeLabel: IntercityPlaces.shortRouteLabel(
                  IntercityPlaces.rawRouteFromTrip(tripData),
                ),
                passengers: newest.passengers,
                userPhone: newest.userPhone,
              ),
              type: 'intercity_booking_pending',
            ),
          );
        }
      }
      _safeNotify();
    });
  }

  void dialogShown() {
    pendingDialogBookingId = null;
    _safeNotify();
  }

  Future<void> setAutoAccept(bool v) async {
    autoAccept = v;
    await _bookingsRepo.setDriverAutoAccept(driverId, v);
    _safeNotify();
  }

  /// Панелдан чиқиш — йўловчи қидирувида рейс **кўриниб туради** (`isActive` ўзгармайди).
  Future<void> leavePanel() async {
    await _db.collection('intercity_drivers').doc(driverId).set(
      {
        'isOnPanel': false,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> openPanel() async {
    await _db.collection('intercity_drivers').doc(driverId).set(
      {
        'isOnPanel': true,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Рейсни тўлиқ тугатиш — актив бронлар бекор, қидирувдан чиқади.
  Future<void> endTripListing() async {
    await _bookingsRepo.cancelActiveBookingsForDriver(
      driverId,
      reason: 'Ҳайдовчи рейсни бекор қилди',
    );
    final scheduleDate = (tripData?['scheduleDate'] as String?)?.trim();
    if (scheduleDate != null && scheduleDate.isNotEmpty) {
      await _schedulesRepo.endTodayWork(driverId: driverId, date: scheduleDate);
    } else {
      final today = DateTime.now();
      final dateStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      await _schedulesRepo.endTodayWork(driverId: driverId, date: dateStr);
    }
    await _db.collection('intercity_drivers').doc(driverId).set(
      {
        'isActive': false,
        'isOnPanel': false,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> accept(String bookingId) async {
    await _bookingsRepo.acceptBooking(bookingId: bookingId, driverId: driverId);
  }

  Future<void> reject(String bookingId) async {
    await _bookingsRepo.rejectBooking(bookingId: bookingId, driverId: driverId);
  }

  Future<void> complete(String bookingId) async {
    final owns = bookings.any(
      (b) => b.id == bookingId && b.driverId == driverId,
    );
    if (!owns) return;
    await _bookingsRepo.completeBooking(
      bookingId: bookingId,
      driverId: driverId,
    );
  }

  Future<void> archive(String bookingId, {required bool archived}) async {
    await _bookingsRepo.setArchived(bookingId: bookingId, archived: archived);
  }

  Future<void> pickUp(String bookingId) async {
    try {
      await _bookingsRepo.markPickedUp(bookingId);
    } catch (e) {
      debugPrint('pickUp error: $e');
    }
  }

  Future<void> startTrip() async {
    try {
      await _ridesRepo.startTrip(driverId);
    } catch (e) {
      debugPrint('startTrip error: $e');
    }
  }

  Future<void> calculatePickupRoute() async {
    if (isCalculatingRoute) return;

    routeError = null;
    isCalculatingRoute = true;
    pickupRoute = null;
    _safeNotify();

    try {
      final from = (tripData?['from'] as String?)?.trim() ?? '';
      final to = (tripData?['to'] as String?)?.trim() ?? '';
      if (from.isEmpty || to.isEmpty) {
        routeError = 'pickup_route_no_trip';
        return;
      }

      double? driverLat;
      double? driverLng;
      if (!kIsWeb) {
        try {
          var perm = await Geolocator.checkPermission();
          if (perm == LocationPermission.denied) {
            perm = await Geolocator.requestPermission();
          }
          if (perm != LocationPermission.denied &&
              perm != LocationPermission.deniedForever &&
              await Geolocator.isLocationServiceEnabled()) {
            final pos = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.medium,
                timeLimit: Duration(seconds: 8),
              ),
            );
            driverLat = pos.latitude;
            driverLng = pos.longitude;
          }
        } catch (_) {}
      }

      pickupRoute = await _pickupRouteService.build(
        bookings: bookings,
        fromCity: from,
        toCity: to,
        driverLat: driverLat,
        driverLng: driverLng,
      );
      _pickupRouteSignature = _pickupSignature(pickupEligibleBookings);
    } on StateError catch (e) {
      routeError = e.message;
    } catch (e, stack) {
      debugPrint('=== PICKUP ROUTE ERROR: $e ===');
      debugPrint('=== STACK: $stack ===');
      routeError = 'pickup_route_failed';
    } finally {
      isCalculatingRoute = false;
      _safeNotify();
    }
  }

  void clearPickupRoute() {
    pickupRoute = null;
    routeError = null;
    _safeNotify();
  }

  void _maybeInvalidatePickupRoute() {
    final sig = _pickupSignature(pickupEligibleBookings);
    if (sig == _pickupRouteSignature) return;
    _pickupRouteSignature = sig;
    if (pickupRoute != null || routeError != null) {
      pickupRoute = null;
      routeError = null;
    }
  }

  String _pickupSignature(List<IntercityBooking> eligible) {
    return eligible
        .map((b) => '${b.id}:${b.pickupLat}:${b.pickupLng}')
        .join('|');
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _tripSub?.cancel();
    _bookingsSub?.cancel();
    _pendingSub?.cancel();
    super.dispose();
  }
}
