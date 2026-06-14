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
      await fn.call(<String, dynamic>{
        'adminPhone': adminPhone,
        'orderIds': orderIds,
        'status': status,
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return 'Xatolik: $e';
    }
  }
}
