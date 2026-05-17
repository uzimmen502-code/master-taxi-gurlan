import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../models/intercity_booking.dart';
import '../../../../repositories/intercity_bookings_repository.dart';

/// Шаҳарлараро такси entry-экранининг тепасида кўрсатиладиган
/// **«Сизнинг бронларингиз»** секцияси учун ҳолат.
///
/// `load()` дан сўнг real-time stream орқали Firestore'дан янгиланиб туради.
class MyBookingsController extends ChangeNotifier {
  MyBookingsController({required IntercityBookingsRepository bookingsRepo})
      : _bookingsRepo = bookingsRepo;

  final IntercityBookingsRepository _bookingsRepo;

  List<IntercityBooking> bookings = const [];
  bool isLoading = true;
  String? errorMessage;

  StreamSubscription<List<IntercityBooking>>? _sub;
  bool _disposed = false;

  /// Барча "тирик" бронлар — pending/confirmed (мижозга кўрсатилади).
  List<IntercityBooking> get activeBookings =>
      bookings.where((b) => b.isActive).toList(growable: false);

  /// Янги/тарих бронлар (агар тепада тарих секцияси керак бўлса).
  List<IntercityBooking> get pastBookings =>
      bookings.where((b) => !b.isActive).toList(growable: false);

  Future<void> load() async {
    if (_sub != null) return;
    final prefs = await SharedPreferences.getInstance();
    final userPhone = prefs.getString('user_phone') ?? '';
    if (userPhone.trim().isEmpty) {
      isLoading = false;
      bookings = const [];
      _safeNotify();
      return;
    }

    _sub = _bookingsRepo.watchByUser(userPhone, limit: 10).listen(
      (list) {
        bookings = list;
        isLoading = false;
        errorMessage = null;
        _safeNotify();
      },
      onError: (e) {
        errorMessage = 'Бронларни юклашда хато: $e';
        isLoading = false;
        _safeNotify();
      },
    );
  }

  Future<void> cancel(String bookingId) async {
    try {
      await _bookingsRepo.cancelBooking(
          bookingId: bookingId, reason: 'мижоз томонидан');
    } on IntercityBookingException catch (e) {
      errorMessage = e.message;
      _safeNotify();
    }
  }

  void clearError() {
    if (errorMessage == null) return;
    errorMessage = null;
    _safeNotify();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
