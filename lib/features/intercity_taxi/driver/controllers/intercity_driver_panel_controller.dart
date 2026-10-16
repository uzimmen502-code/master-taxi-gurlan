import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../models/intercity_booking.dart';
import '../../../../models/intercity_pickup_route.dart';
import '../../../../repositories/intercity_bookings_repository.dart';
import '../../../../repositories/intercity_rides_repository.dart';
import '../../../../repositories/schedules_repository.dart';
import '../../../../repositories/taxi_billing_repository.dart';
import '../../../../services/intercity_pickup_route_service.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../services/trip_change_settlement.dart';
import '../../intercity_driver_alert_text.dart';
import '../../../../services/notification_delivery.dart';
import '../../../../utils/intercity_places.dart';

/// "Reysni tugatish" natijasi (UI aniq xabar ko'rsatishi uchun).
class EndListingResult {
  const EndListingResult({
    required this.listingClosed,
    this.refundFailed = false,
    this.bookingsCancelled = 0,
    this.bookingsFailed = 0,
  });

  /// E'lon yopildi (`intercity_drivers.isActive=false`) — yangi bron kela olmaydi.
  final bool listingClosed;

  /// Komissiyani qaytarish (serverga bekor so'rovi) muvaffaqiyatsiz.
  final bool refundFailed;
  final int bookingsCancelled;

  /// Bekor qilinmay qolgan bronlar (ro'yxatni o'qib bo'lmasa kamida 1).
  final int bookingsFailed;

  bool get ok => listingClosed && !refundFailed && bookingsFailed == 0;
}

/// [EndListingResult] → foydalanuvchiga ko'rsatiladigan l10n kaliti
/// (`null` — hammasi joyida, xabar kerak emas). Eng muhim muammo birinchi:
/// e'lon yopilmadi > bronlar qoldi > komissiya qaytmadi.
String? intercityEndTripNoticeKey(EndListingResult r) {
  if (!r.listingClosed) return 'ic_end_failed';
  if (r.bookingsFailed > 0) return 'ic_end_bookings_failed';
  if (r.refundFailed) return 'ic_end_refund_failed';
  return null;
}

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
    FirebaseFirestore? db,
    TaxiBillingRepository? billingRepo,
    Future<Position?> Function()? lastKnownPosition,
  })  : _bookingsRepo = bookingsRepo,
        _schedulesRepo = schedulesRepo,
        _pickupRouteService = pickupRouteService ?? IntercityPickupRouteService(),
        _ridesRepoOverride = ridesRepo,
        _dbOverride = db,
        _billingOverride = billingRepo,
        _lastKnownPosition = lastKnownPosition ?? _defaultLastKnownPosition;

  final String driverId;
  final String driverName;
  final String driverPhone;
  final String driverCar;
  final String driverPlate;

  final IntercityBookingsRepository _bookingsRepo;
  final SchedulesRepository _schedulesRepo;
  final IntercityPickupRouteService _pickupRouteService;

  // Firebase'ga bog'liq obyektlar dangasa yaratiladi: test fake bersa
  // Firebase.initializeApp talab qilinmaydi.
  final IntercityRidesRepository? _ridesRepoOverride;
  final FirebaseFirestore? _dbOverride;
  final TaxiBillingRepository? _billingOverride;
  final Future<Position?> Function() _lastKnownPosition;

  late final IntercityRidesRepository _ridesRepo =
      _ridesRepoOverride ?? IntercityRidesRepository();
  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;
  late final TaxiBillingRepository _billing =
      _billingOverride ?? TaxiBillingRepository();

  static Future<Position?> _defaultLastKnownPosition() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

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

  /// Oxirgi "reysni tugatish" urinishi to'liq bajarilmagan (komissiya
  /// qaytarilmadi yoki bronlar bekor qilinmay qoldi) — UI qayta urinishni
  /// taklif qiladi.
  bool endIncomplete = false;

  /// Hali bekor qilinmagan (kutilayotgan/tasdiqlangan) bronlar bormi.
  bool get hasOpenBookings => bookings.any((b) => b.isActive);

  /// "Reysni tugatish" tugmasi ko'rinadimi: e'lon ochiq, yoki oldingi urinish
  /// to'liq tugamagan, yoki bekor qilinmagan bronlar qolgan.
  bool get canEndTrip => isListed || endIncomplete || hasOpenBookings;

  /// Рейсни тўлиқ тугатиш — қидирувдан чиқади, актив бронлар бекор.
  ///
  /// TARTIB muhim (data integrity): AVVAL e'lon yopiladi (yangi bron kira
  /// olmaydi — server `driver_inactive` qaytaradi), KEYIN komissiya
  /// qaytariladi, ENG OXIRIDA bronlar bekor qilinadi. Avval bronlar bekor
  /// qilinardi, e'lon esa ochiq qolardi: shu oraliqda yangi bron "o'tib"
  /// ketishi mumkin edi. Har bir bosqich xatosi [EndListingResult] da.
  ///
  /// D-TAXI-15/16, D-TAXI-CANCEL-9: billing рейси бор бўлса серверга
  /// айтилади — `cancelled` + refund, жўнашдан КЕЙИН ҳам. Ёлғон отмена фақат
  /// далил билан (кейинги рейс эълонида қайта баҳоланади). Сервер томони
  /// idempotent — qayta urinish xavfsiz.
  Future<EndListingResult> endTripListing() async {
    // Bronlar bekor bo'lishidan OLDIN hisoblanadi (fraud signali).
    final billingTripId = (tripData?['billingTripId'] as String?)?.trim();
    final hadBooking = confirmedBookings.isNotEmpty;

    // 1) E'lonni yopish.
    try {
      await _db.collection('intercity_drivers').doc(driverId).set(
        {
          'isActive': false,
          'isOnPanel': false,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      // E'lon yopilmadi — hech narsa bekor qilinmaydi (holat izchil qoladi).
      debugPrint('endTripListing: listing close failed: $e');
      endIncomplete = true;
      _safeNotify();
      return const EndListingResult(listingClosed: false);
    }

    // 2) Jadval (schedules/queue) yopiladi — e'lon allaqachon yopiq, shuning
    // uchun xato bo'lsa ham davom etamiz (faqat logda).
    final scheduleDate = (tripData?['scheduleDate'] as String?)?.trim();
    final dateStr = (scheduleDate != null && scheduleDate.isNotEmpty)
        ? scheduleDate
        : _todayStr();
    final scheduleClosed =
        await _schedulesRepo.endTodayWork(driverId: driverId, date: dateStr);
    if (!scheduleClosed) {
      debugPrint('endTripListing: schedules close failed ($driverId/$dateStr)');
    }

    // 3) Komissiyani qaytarish (serverga bekor).
    var refundFailed = false;
    if (billingTripId != null && billingTripId.isNotEmpty) {
      Position? pos;
      try {
        pos = await _lastKnownPosition();
      } catch (_) {}
      try {
        await _billing.cancel(
          tripId: billingTripId,
          hadAvaBooking: hadBooking,
          driverLat: pos?.latitude,
          driverLng: pos?.longitude,
        );
      } catch (e) {
        debugPrint('endTripListing: billing cancel failed: $e');
        refundFailed = true;
      }
    }

    // 4) Bronlarni bekor qilish (yo'lovchilarga server xabar beradi).
    var cancelled = 0;
    var failed = 0;
    try {
      final r = await _bookingsRepo.cancelActiveBookingsForDriverDetailed(
        driverId,
        reason: 'Ҳайдовчи рейсни бекор қилди',
      );
      cancelled = r.cancelled;
      failed = r.failed;
    } catch (e) {
      debugPrint('endTripListing: bookings lookup failed: $e');
      failed = 1; // ro'yxat o'qilmadi — bronlar holati noma'lum
    }

    endIncomplete = refundFailed || failed > 0;
    _safeNotify();
    return EndListingResult(
      listingClosed: true,
      refundFailed: refundFailed,
      bookingsCancelled: cancelled,
      bookingsFailed: failed,
    );
  }

  String _todayStr() {
    final today = DateTime.now();
    return '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
  }

  /// D-TAXI-CANCEL-3 — рейсни КЕЙИНГА СУРИШ: бекор ЭМАС. `tripId` ва
  /// комиссия сақланади, фақат сана/вақт ўзгаради (сервер шуни
  /// кафолатлайди). Эълон (`intercity_drivers`) ҳам янги санага ўтади.
  ///
  /// `billingTripId` бўлмаса (эски эълон) фақат эълон санаси ўзгаради.
  Future<void> rescheduleTrip({
    required DateTime departureAt,
    required String scheduleDate,
    required String startTime,
  }) async {
    final billingTripId = (tripData?['billingTripId'] as String?)?.trim();
    if (billingTripId != null && billingTripId.isNotEmpty) {
      // Yo'lovchilar bronlari va xabarlar SERVERda (`rescheduleTaxiTrip`):
      // haydovchi ilovasi boshqa odamlarning hujjatiga yozmaydi. Quyida
      // faqat haydovchining O'Z e'loni (`intercity_drivers/{driverId}`) yangilanadi.
      await _billing.reschedule(
        tripId: billingTripId,
        departureAt: departureAt,
        scheduleDate: scheduleDate,
        startTime: startTime,
      );
    }
    final parts = startTime.split(':');
    final hour = int.tryParse(parts.first) ?? 8;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    await _db.collection('intercity_drivers').doc(driverId).set(
      {
        'scheduleDate': scheduleDate,
        'hour': hour,
        'minute': minute,
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

  /// Yakunlash — fare/cash dialog → booking complete → qaytim settlement.
  Future<String?> completeWithFare({
    required String bookingId,
    required int fare,
    required int cashPaid,
  }) async {
    IntercityBooking? booking;
    for (final b in bookings) {
      if (b.id == bookingId) {
        booking = b;
        break;
      }
    }
    if (booking == null || booking.driverId != driverId) {
      return 'booking_not_found';
    }
    await _bookingsRepo.completeBooking(
      bookingId: bookingId,
      driverId: driverId,
    );
    if (booking.userPhone.isNotEmpty && cashPaid > fare) {
      final change = cashPaid - fare;
      final outcome = await TripChangeSettlement.settle(
        passengerPhone: canonicalPhoneId(booking.userPhone),
        tripId: bookingId,
        opId: 'settle_ic_$bookingId',
        change: change,
      );
      if (outcome.status == TripChangeSettlementStatus.failedPermanent) {
        return outcome.userMessage ?? 'settlement_failed';
      }
      if (outcome.status == TripChangeSettlementStatus.deferred) {
        return outcome.userMessage;
      }
    }
    return null;
  }

  Future<void> complete(String bookingId) async {
    IntercityBooking? booking;
    for (final b in bookings) {
      if (b.id == bookingId) {
        booking = b;
        break;
      }
    }
    if (booking == null || booking.driverId != driverId) return;
    await completeWithFare(
      bookingId: bookingId,
      fare: booking.totalAmount,
      cashPaid: booking.totalAmount,
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

  /// Safarni boshlash. Muvaffaqiyatli bo'lsa `true`; xato bo'lsa `false`
  /// (UI haqiqiy natijani ko'rsatadi — avval xato yutilib doim "boshlandi" edi).
  Future<bool> startTrip() async {
    try {
      await _ridesRepo.startTrip(driverId);
      return true;
    } catch (e) {
      debugPrint('startTrip error: $e');
      return false;
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
