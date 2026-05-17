import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../models/driver_client_stats.dart';
import '../../../../models/intercity_booking.dart';
import '../../../../models/intercity_ride.dart';
import '../../../../repositories/intercity_bookings_repository.dart';
import '../../../../repositories/intercity_rides_repository.dart';
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

  // ─── Йўналиш танлови ───────────────────────────────────────────────

  void selectFrom(String loc) {
    selectedFromLocation = loc;
    notifyListeners();
  }

  void selectTo(String loc) {
    selectedToLocation = loc;
    selectedDistrict = loc.contains('•') ? loc.split('•')[1].trim() : null;
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
    notifyListeners();
  }

  void setIsToday(bool v) {
    if (isToday == v) return;
    isToday = v;
    notifyListeners();
  }

  void incPassengers() {
    if (passengers >= 4) return;
    passengers += 1;
    notifyListeners();
  }

  void decPassengers() {
    if (passengers <= 1) return;
    passengers -= 1;
    notifyListeners();
  }

  // ─── Қидирув ────────────────────────────────────────────────────────

  Future<void> search() async {
    if (selectedFromLocation == null || selectedToLocation == null) {
      errorMessage = 'Илтимос, йўналишни танланг';
      notifyListeners();
      return;
    }
    isLoading = true;
    hasSearched = true;
    notifyListeners();

    final now = DateTime.now();
    final base = isToday ? now : now.add(const Duration(days: 1));
    final fromCity = IntercityPlaces.extractCity(selectedFromLocation ?? '');
    final toCity = IntercityPlaces.extractCity(selectedToLocation ?? '');
    final district = selectedDistrict ?? '';

    final found = await _ridesRepo.getActiveRides(
      fromCity: fromCity,
      toCity: toCity,
      district: district,
      baseDate: base,
    );

    // Passengers soni bo'yicha filter
    final filtered = found
        .where((r) => r.availableSeats >= passengers)
        .toList();

    // Rating bo'yicha sort (yuqori reyting birinchi)
    filtered.sort((a, b) => b.rating.compareTo(a.rating));
    rides = filtered;

    if (filtered.isEmpty && found.isNotEmpty) {
      // Haydovchilar bor, lekin joy yetarli emas
      errorMessage = 'Tanlangan yo\'lovchilar soniga mos joy yo\'q. '
          'Yo\'lovchilar sonini kamaytiring.';
    } else if (filtered.isEmpty) {
      errorMessage = 'Hozir bu yo\'nalishda haydovchi yo\'q. '
          'Keyinroq urinib ko\'ring yoki boshqa yo\'nalishni tanlang.';
    } else {
      errorMessage = null;
    }

    isLoading = false;
    notifyListeners();
  }

  void resetSearch() {
    hasSearched = false;
    rides = const [];
    isLoading = false;
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
  /// Қайтариш қиймати — муваффақиятли бўлса `IntercityBooking`, акс ҳолда `null`
  /// ва `errorMessage` тўлдирилади (UI Snackbar'да кўрсатади).
  Future<IntercityBooking?> bookRide(IntercityRide ride) async {
    if (isBooking) return null;

    final prefs = await SharedPreferences.getInstance();
    final userPhone = prefs.getString('user_phone') ?? '';
    final userName = prefs.getString('user_name') ?? '';

    if (userPhone.trim().isEmpty) {
      errorMessage = 'Профилда телефон рақамингизни киритинг';
      notifyListeners();
      return null;
    }

    isBooking = true;
    notifyListeners();

    try {
      final booking = await _bookingsRepo.createBooking(
        driverId: ride.id,
        driverPhone: ride.phoneNumber,
        driverName: ride.driverName,
        carNumber: ride.carNumber,
        userPhone: userPhone,
        userName: userName.isEmpty ? 'Йўловчи' : userName,
        fromCity: ride.fromCity,
        toCity: ride.toCity,
        district: ride.district,
        passengers: passengers,
        pricePerSeat: ride.price,
        departureTime: ride.departureTime,
      );

      lastBooking = booking;
      isBooking = false;
      notifyListeners();
      return booking;
    } on IntercityBookingException catch (e) {
      errorMessage = e.message;
      isBooking = false;
      notifyListeners();
      return null;
    } catch (e) {
      errorMessage = 'Бронлашда хатолик: $e';
      isBooking = false;
      notifyListeners();
      return null;
    }
  }
}
