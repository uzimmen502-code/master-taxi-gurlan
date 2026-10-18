import 'package:cloud_functions/cloud_functions.dart';

import '../utils/realty_counts_validation.dart';

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

  /// Объект сонлари: бепул лимит, ахборот пакети, профессионал режалар.
  /// Сервер текширади ва `admin_audit`га ёзади (`adminSetRealtyCounts`).
  /// Хатода [StateError] — матни админга тушунарли (`realtyCountsServerError`).
  Future<void> saveCounts({
    required String adminPhone,
    required int? freeLimit,
    required List<Map<String, int>> packages,
    required List<Map<String, Object>> proPlans,
  }) async {
    try {
      await _functions.httpsCallable('adminSetRealtyCounts').call({
        'adminPhone': adminPhone,
        'freeLimit': freeLimit,
        'packages': packages,
        'proPlans': proPlans,
      });
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      final reason = details is Map && details['reason'] != null
          ? '${details['reason']}'
          : (e.message ?? e.code);
      throw StateError(realtyCountsServerError(reason));
    }
  }

  Future<void> _call(String name, Map<String, dynamic> data) async {
    try {
      await _functions.httpsCallable(name).call(data);
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? e.code);
    }
  }
}
