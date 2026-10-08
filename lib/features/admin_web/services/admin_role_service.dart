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

  /// Superadmin: panel roli bor foydalanuvchiga yangi tasodifiy PIN
  /// (`adminSetAdminPin`). PIN faqat shu javobda keladi — serverda xesh.
  Future<({String? pin, String? error})> setAdminPin({
    required String targetPhone,
  }) async {
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('adminSetAdminPin')
          .call<Map<String, dynamic>>({'targetPhone': targetPhone});
      return (pin: res.data['pin'] as String?, error: null);
    } on FirebaseFunctionsException catch (e) {
      if (e.message == 'ADMIN_PIN_TARGET_NOT_PANEL_ROLE') {
        return (pin: null, error: 'Avval panel roli bering (admin/finance/…).');
      }
      return (pin: null, error: e.message ?? e.code);
    } catch (e) {
      return (pin: null, error: 'Xatolik: $e');
    }
  }
}
