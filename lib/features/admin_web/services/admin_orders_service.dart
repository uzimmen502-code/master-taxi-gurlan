import 'package:cloud_functions/cloud_functions.dart';

/// Admin web buyurtma status — Cloud Functions (Firestore `isAdmin()` emas).
class AdminOrdersService {
  AdminOrdersService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<String?> setOrderStatus({
    required String adminPhone,
    required String orderId,
    required String status,
  }) async {
    try {
      final fn = _functions.httpsCallable('adminSetOrderStatus');
      await fn.call(<String, dynamic>{
        'adminPhone': adminPhone,
        'orderId': orderId,
        'status': status,
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return 'Xatolik: $e';
    }
  }

  Future<String?> setOrderStatusBatch({
    required String adminPhone,
    required List<String> orderIds,
    required String status,
  }) async {
    try {
      final fn = _functions.httpsCallable('adminSetOrderStatusBatch');
      final res = await fn.call<Map<String, dynamic>>(<String, dynamic>{
        'adminPhone': adminPhone,
        'orderIds': orderIds,
        'status': status,
      });
      // Сервер ҳолати ўзгариб кетган (масалан, мижоз бекор қилган)
      // буюртмаларни ўтказиб юборади — админ буни билиши керак.
      final skipped = res.data['skipped'];
      if (skipped is List && skipped.isNotEmpty) {
        final done = orderIds.length - skipped.length;
        return '$done та бажарилди, ${skipped.length} та ўтказиб юборилди '
            '(ҳолати ўзгарган).';
      }
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return 'Xatolik: $e';
    }
  }
}
