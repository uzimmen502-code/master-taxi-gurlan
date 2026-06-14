import 'package:cloud_functions/cloud_functions.dart';

/// Web admin — foydalanuvchi rolini Cloud Function orqali o'zgartirish.
class AdminRoleService {
  Future<String?> setUserRole({
    required String adminPhone,
    required String targetPhone,
    required String role,
  }) async {
    try {
      final fn = FirebaseFunctions.instance.httpsCallable('setUserRoleByAdmin');
      await fn.call(<String, dynamic>{
        'adminPhone': adminPhone,
        'targetPhone': targetPhone,
        'role': role,
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found' || e.code == 'unimplemented') {
        return 'Server funksiyasi deploy qilinmagan: setUserRoleByAdmin';
      }
      return e.message ?? 'Rol o\'zgartirilmadi (${e.code})';
    } catch (e) {
      return 'Xatolik: $e';
    }
  }
}
