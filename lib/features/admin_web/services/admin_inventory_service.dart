import 'package:cloud_functions/cloud_functions.dart';

/// Admin web — ombor (`soldToday`) amallari Cloud Functions orqali.
///
/// «Сотилган = 0» avval klientdan `soldToday: 0` yozardi va ochiq
/// to'lanmagan buyurtmalar rezervini yo'qotardi (admin auditi O-8).
/// Server (`adminResetItemSoldToday`) kunlik reset qoidasi bilan rezervni
/// saqlab qayta hisoblaydi. Admin roli token telefonidan aniqlanadi.
class AdminInventoryService {
  AdminInventoryService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// [kind]: `bread` | `extra` | `food` | `platform`.
  /// Natija — reset'dan keyingi `soldToday` (ochiq buyurtmalar rezervi).
  Future<num> resetItemSold({required String kind, required String id}) async {
    try {
      final res = await _functions
          .httpsCallable('adminResetItemSoldToday')
          .call<Map<String, dynamic>>({'kind': kind, 'id': id});
      return (res.data['soldToday'] as num?) ?? 0;
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? e.code);
    }
  }
}
