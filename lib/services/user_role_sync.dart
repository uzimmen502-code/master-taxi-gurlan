import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/formatters.dart';

/// Foydalanuvchi roli: **admin/superadmin/dispatcher** faqat Firestore орқали.
///
/// Mobil ilovada SharedPreferences (APK yangilanganda ham) админ ролини
/// ishonchli deb qabul qilmaymiz — serverdagi `users/{uid}.role` bilan tekshiramiz.
class UserRoleSync {
  UserRoleSync({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const privilegedRoles = {'admin', 'superadmin', 'dispatcher'};

  static bool isPrivileged(String role) =>
      privilegedRoles.contains(role.trim().toLowerCase());

  /// Ҳайдовчи тасдиқланганidan keyin prefs'ni darhol `driver` qilish.
  static Future<void> forceSyncDriver() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', 'driver');
    try {
      final phone = prefs.getString('user_phone') ?? '';
      if (phone.isEmpty) return;
      final sync = UserRoleSync();
      final fsRole = await sync.fetchFirestoreRole(phone);
      final role = (fsRole != null && fsRole.trim().isNotEmpty)
          ? fsRole.trim().toLowerCase()
          : 'driver';
      await prefs.setString('user_role', role);
    } catch (_) {
      // Firestore ishlamasa — local `driver` saqlanadi.
    }
  }

  /// Firestore ustuvor (faqat privileged); aks holda server yoki local.
  static String reconcile({
    required String localRole,
    required String? firestoreRole,
  }) {
    const protectedRoles = {'admin', 'superadmin', 'dispatcher'};
    final fs = (firestoreRole ?? '').trim();
    final fsNorm = fs.toLowerCase();

    // Firestore admin role ALWAYS wins — never overwrite with local prefs
    if (protectedRoles.contains(fsNorm)) return fsNorm;

    final local = localRole.trim().isEmpty ? 'user' : localRole.trim();
    if (isPrivileged(local)) {
      return fs.isNotEmpty ? fsNorm : 'user';
    }
    if (fs.isNotEmpty) return fsNorm;
    return local;
  }

  Future<String?> fetchFirestoreRole(String uid) async {
    if (phoneDigits(uid).length < 9) return null;
    try {
      for (final id in userDocIdCandidates(uid)) {
        final snap = await _db.collection('users').doc(id).get();
        if (snap.exists) {
          return snap.data()?['role'] as String?;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// `user_phone` бўйича ролни Firestore билан moslashtiradi, prefs'ни янгилaydi.
  Future<String> syncToPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getString('user_role') ?? 'user';
    final phone = prefs.getString('user_phone') ?? '';
    final uid = phoneDigits(phone);

    if (uid.length < 9) {
      if (isPrivileged(local)) {
        await prefs.setString('user_role', 'user');
        return 'user';
      }
      return local;
    }

    final fsRole = await fetchFirestoreRole(uid);
    final resolved = reconcile(localRole: local, firestoreRole: fsRole);
    if (resolved != local) {
      await prefs.setString('user_role', resolved);
    }
    return resolved;
  }
}

/// Client `updateProfile` / `quickSaveRole` учун рухсат etilgan rollar.
bool isClientAssignableRole(String role) {
  const allowed = {'user', 'driver', 'courier'};
  return allowed.contains(role.trim().toLowerCase());
}
