import 'package:cloud_functions/cloud_functions.dart';

/// Admin web — 🏠 Кўчмас мулк модерацияси.
///
/// `admin_ev_charging_service.dart` билан бир хил нақш: текширув
/// сервердаги `assertAdmin()` да, Firestore rules'га таянилмайди.
class AdminRealtyService {
  AdminRealtyService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// `active` | `pending` | `blocked`.
  Future<void> setStatus({
    required String adminPhone,
    required String listingId,
    required String status,
    String adminNote = '',
  }) {
    return _call('adminSetRealtyStatus', {
      'adminPhone': adminPhone,
      'listingId': listingId,
      'status': status,
      if (adminNote.trim().isNotEmpty) 'adminNote': adminNote.trim(),
    });
  }

  Future<void> deleteListing({
    required String adminPhone,
    required String listingId,
  }) {
    return _call('adminDeleteRealtyListing', {
      'adminPhone': adminPhone,
      'listingId': listingId,
    });
  }

  Future<void> _call(String name, Map<String, dynamic> data) async {
    try {
      await _functions.httpsCallable(name).call(data);
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? e.code);
    }
  }
}
