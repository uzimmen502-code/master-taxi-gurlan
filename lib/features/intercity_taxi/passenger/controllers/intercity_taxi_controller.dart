import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../models/driver_client_stats.dart';
import '../../../../models/intercity_booking.dart';
import '../../../../models/intercity_ride.dart';
import '../../../../repositories/intercity_bookings_repository.dart';
import '../../../../repositories/intercity_rides_repository.dart'
    show IntercityRidesRepository;
import '../../../../utils/intercity_places.dart';

/// Шаҳарлараро такси yo'lovchi entry-экранининг ҳолатини бошқаради:
///   - Йўналиш (from/to) ва Тошкент тумани танлови
///   - "Бугун / Эртага" тугмалари ҳамда йўловчилар сони
///   - Reyslarни Firestore-dан олиш (хатолик ёки бўш — demo fallback)
///   - **Реал бронь яратиш** (transactional, seat decrement, доимий мижоз
///     aggregation, ҳайдовчига notification)
///   - Танланган рейс учун доимий мижоз ҳолатини текшириш
class IntercityTaxiController extends ChangeNotifier {
  IntercityTaxiController({
    required IntercityRidesRepository ridesRepo,
    required IntercityBookingsRepository bookingsRepo,
  })  : _ridesRepo = ridesRepo,
        _bookingsRepo = bookingsRepo;

  final IntercityRidesRepository _ridesRepo;
  final IntercityBookingsRepository _bookingsRepo;

  String? selectedFromLocation;
  String? selectedToLocation;
  String? selectedDistrict;
  bool isToday = true;
  int passengers = 1;

  List<IntercityRide> rides = const [];
  bool isLoading = false;
  bool _isSearching = false;
  bool get isSearching => _isSearching;
  bool hasSearched = false;
  String? errorMessage;

  /// Бронь жараёни — ҳозирда юбориляптими?
  bool isBooking = false;

  /// Энг охирги муваффақиятли бронь (BookingConfirmationSheet-да кўрсатилади).
  IntercityBooking? lastBooking;

  /// Танланган рейс учун **доимий мижоз** ҳолати — `isLoyal`, `bookingCount`...
  /// `null` → ҳали юкланмаган ёки фойдаланувчи бу ҳайдовчида биринчи марта.
  DriverClientStats? loyaltyForSelected;

  /// Қайси рейс учун `loyaltyForSelected` юкланган (race condition'дан асраш).
  String? _loyaltyRideId;

  StreamSubscription<List<IntercityRide>>? _ridesSub;
  List<IntercityRide> _allRides = const [];

  // ─── Йўналиш танлови ───────────────────────────────────────────────

  void selectFrom(String loc) {
    selectedFromLocation = loc.trim().isEmpty ? null : loc;
    notifyListeners();
  }

  void selectTo(String loc) {
    if (loc.trim().isEmpty) {
      selectedToLocation = null;
      selectedDistrict = null;
    } else {
      selectedToLocation = loc;
      selectedDistrict = loc.contains('•') ? loc.split('•')[1].trim() : null;
    }
    notifyListeners();
  }

  void clearFrom() {
    selectedFromLocation = null;
    notifyListeners();
  }

  void clearTo() {
    selectedToLocation = null;
    selectedDistrict = null;
    notifyListeners();
  }

  void setDistrict(String d) {
    selectedDistrict = d;
    selectedToLocation = 'Тошкент ш. • $d';
    notifyListeners();
  }

  void swap() {
    final tmp = selectedFromLocation;
    selectedFromLocation = selectedToLocation;
    selectedToLocation = tmp;
    if (selectedToLocation != null && selectedToLocation!.contains('•')) {
      selectedDistrict = selectedToLocation!.split('•')[1].trim();
    } else {
      selectedDistrict = null;
    }
    notifyListeners();
  }

  void incPassengersForSeats(int maxSeats) {
    final max = maxSeats.clamp(1, 4);
    if (passengers >= max) return;
    passengers += 1;
    notifyListeners();
  }

  void decPassengersForSeats() {
    if (passengers <= 1) return;
    passengers -= 1;
    notifyListeners();
  }

  void resetPassengersForRide(int maxSeats) {
    final max = maxSeats.clamp(1, 4);
    final next = 1.clamp(1, max);
    if (passengers == next) return;
    passengers = next;
    notifyListeners();
  }

  /// Bron paneli bekor qilinganda qidiruv filterini 1 yo'lovchiga qaytaradi.
  void resetPassengers() {
    if (passengers == 1 && !hasSearched) return;
    passengers = 1;
    if (hasSearched) {
      _refilterRides();
    } else {
      notifyListeners();
    }
  }

  /// Qidiruv filteri: forma yo'lovchi sonini ko'rsatmaydi — doim 1 dan filtrlash.
  void resetSearchPassengerCount() => resetPassengers();

  void setIsToday(bool v) {
    if (isToday == v) return;
    isToday = v;
    notifyListeners();
  }

  void incPassengers() {
    if (passengers >= 4) return;
    passengers += 1;
    if (hasSearched) {
      _refilterRides();
    } else {
      notifyListeners();
    }
  }

  void decPassengers() {
    if (passengers <= 1) return;
    passengers -= 1;
    if (hasSearched) {
      _refilterRides();
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _ridesSub?.cancel();
    super.dispose();
  }

  // ─── Қидирув ────────────────────────────────────────────────────────

  /// Matn maydonlaridan yo'nalishni controller'ga yozish (ro'yxatdan tanlanmasa ham).
  bool commitRouteFromText({
    required String fromText,
    required String toText,
  }) {
    final from = IntercityPlaces.normalizeLocation(fromText);
    final to = IntercityPlaces.normalizeLocation(toText);
    if (from.isEmpty || to.isEmpty) return false;

    selectedFromLocation = from;
    selectedToLocation = to;
    selectedDistrict = to.contains('•') ? to.split('•')[1].trim() : null;
    notifyListeners();
    return true;
  }

  Future<void> search() async {
    final from = selectedFromLocation?.trim() ?? '';
    final to = selectedToLocation?.trim() ?? '';
    if (from.isEmpty || to.isEmpty) {
      errorMessage = 'select_route';
      notifyListeners();
      return;
    }

    passengers = 1;
    _isSearching = true;
    isLoading = true;
    hasSearched = true;
    rides = const [];
    _allRides = const [];
    notifyListeners();

    try {
      final now = DateTime.now();
      final base = isToday ? now : now.add(const Duration(days: 1));
      final fromCity = IntercityPlaces.extractCity(from);
      final toCity = IntercityPlaces.extractCity(to);
      final district = selectedDistrict ?? '';

      await _ridesSub?.cancel();
      _ridesSub = _ridesRepo
          .watchActiveRides(
            fromCity: fromCity,
            toCity: toCity,
            passengerFromRaw: from,
            passengerToRaw: to,
            district: district,
            baseDate: base,
          )
          .listen(
        (found) => _applyRideResults(found),
        onError: (e) {
          _isSearching = false;
          isLoading = false;
          errorMessage = e.toString().contains('permission-denied')
              ? 'search_permission_denied'
              : 'search_error_internet';
          rides = const [];
          notifyListeners();
        },
      );
    } catch (e) {
      _isSearching = false;
      isLoading = false;
      errorMessage = 'search_error_internet';
      notifyListeners();
    }
  }

  void _applyRideResults(List<IntercityRide> found) {
    _allRides = found;
    _refilterRides();
  }

  void _refilterRides() {
    final filtered =
        _allRides.where((r) => r.availableSeats >= passengers).toList();
    filtered.sort((a, b) => b.rating.compareTo(a.rating));
    rides = filtered;

    if (filtered.isEmpty && _allRides.isNotEmpty) {
      errorMessage = 'no_seats_for_passenger_count';
    } else if (filtered.isEmpty) {
      errorMessage = isToday ? 'no_driver_today' : 'no_driver_tomorrow';
    } else {
      errorMessage = null;
    }

    isLoading = false;
    _isSearching = false;
    notifyListeners();
  }

  /// Firestore snapshot kelguncha ro'yxatdagi o'rin/jins ko'rsatkichlarini sync qilish.
  void applyLocalBookingStats({
    required String driverId,
    required String userGender,
    required int passengerDelta,
  }) {
    if (passengerDelta == 0) return;
    _allRides = _allRides.map((r) {
      if (r.id != driverId) return r;
      final seats = (r.availableSeats - passengerDelta).clamp(0, 99);
      var male = r.maleCount;
      var female = r.femaleCount;
      if (userGender == 'male') {
        male = (male + passengerDelta).clamp(0, 99);
      } else if (userGender == 'female') {
        female = (female + passengerDelta).clamp(0, 99);
      }
      return r.copyWith(
        availableSeats: seats,
        maleCount: male,
        femaleCount: female,
      );
    }).toList(growable: false);
    _refilterRides();
  }

  void resetSearch() {
    _ridesSub?.cancel();
    _ridesSub = null;
    hasSearched = false;
    rides = const [];
    _allRides = const [];
    passengers = 1;
    isLoading = false;
    _isSearching = false;
    lastBooking = null;
    loyaltyForSelected = null;
    _loyaltyRideId = null;
    notifyListeners();
  }

  void clearError() {
    if (errorMessage == null) return;
    errorMessage = null;
    notifyListeners();
  }

  void clearLastBooking() {
    if (lastBooking == null) return;
    lastBooking = null;
    notifyListeners();
  }

  // ─── Доимий мижоз ҳолатини олиш ─────────────────────────────────────

  /// Bron sheet ochilganda chaqiriladi — fon orqali oxirgi ma'lumotni
  /// chaqirsoq, sheet "Доимий мижоз" badge bilan ko'rsatadi.
  Future<void> loadLoyaltyFor(IntercityRide ride) async {
    _loyaltyRideId = ride.id;
    loyaltyForSelected = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final userPhone = prefs.getString('user_phone') ?? '';
    if (userPhone.isEmpty) return;

    final stats = await _bookingsRepo.getDriverClient(
      driverId: ride.id,
      userPhone: userPhone,
    );
    // Boshqa rayd tanlangan bo'lsa — bu javobni e'tibor bermaslik
    if (_loyaltyRideId != ride.id) return;
    loyaltyForSelected = stats;
    notifyListeners();
  }

  void clearLoyalty() {
    if (loyaltyForSelected == null && _loyaltyRideId == null) return;
    loyaltyForSelected = null;
    _loyaltyRideId = null;
    notifyListeners();
  }

  // ─── Реал бронь ───────────────────────────────────────────────────

  /// Танланган рейс учун бронь яратади.
  /// `(booking, errorKey)` — sheet ichida xato ko‘rsatish uchun; snackbar emas.
  Future<(IntercityBooking?, String?)> bookRide(
    IntercityRide ride, {
    required String defaultPassengerName,
  }) async {
    if (isBooking) return (null, null);

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return (null, 'auth_required_to_order');
    }

    try {
      await currentUser.getIdToken(true);
    } catch (_) {
      return (null, 'auth_required_to_order');
    }

    if (ride.price <= 0 || ride.price * passengers <= 0) {
      return (null, 'ride_not_accepting');
    }

    final prefs = await SharedPreferences.getInstance();
    final userPhone = prefs.getString('user_phone') ?? '';
    final userName = prefs.getString('user_name') ?? '';

    if (userPhone.trim().isEmpty) {
      return (null, 'fill_phone_in_profile');
    }

    final userGender = prefs.getString('user_gender') ?? 'male';
    final userBirthDate = prefs.getString('user_birth_date') ?? '';

    isBooking = true;
    notifyListeners();

    try {
      final booking = await _bookingsRepo.createBooking(
        driverId: ride.id,
        driverPhone: ride.phoneNumber,
        driverName: ride.driverName,
        carNumber: ride.carNumber,
        userPhone: userPhone,
        userName: userName.trim().isEmpty
            ? defaultPassengerName
            : userName.trim(),
        userGender: userGender,
        userBirthDate: userBirthDate,
        fromCity: ride.fromCity,
        toCity: ride.toCity,
        district: ride.district,
        passengers: passengers,
        pricePerSeat: ride.price,
        departureTime: ride.departureTime,
      );

      lastBooking = booking;
      applyLocalBookingStats(
        driverId: ride.id,
        userGender: userGender,
        passengerDelta: passengers,
      );
      resetSearchPassengerCount();
      isBooking = false;
      notifyListeners();
      return (booking, null);
    } on IntercityBookingException catch (e) {
      final key = switch (e.kind) {
        IntercityBookingErrorKind.alreadyBooked => 'booking_already_active',
        IntercityBookingErrorKind.alreadyActive => 'booking_already_active',
        IntercityBookingErrorKind.notEnoughSeats => 'not_enough_seats',
        IntercityBookingErrorKind.driverInactive => 'ride_not_accepting',
        IntercityBookingErrorKind.driverNotFound => 'driver_profile_not_found',
        IntercityBookingErrorKind.permissionDenied => 'booking_permission_denied',
        IntercityBookingErrorKind.unknown => e.message,
      };
      isBooking = false;
      notifyListeners();
      return (null, key);
    } catch (e) {
      final msg = e.toString();
      isBooking = false;
      notifyListeners();
      return (
        null,
        msg.contains('permission-denied')
            ? 'booking_permission_denied'
            : 'booking_error|$e',
      );
    }
  }
}
