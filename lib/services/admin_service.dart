import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/formatters.dart';
import 'user_role_sync.dart';

/// Админ rolени **бир жойдан** тeкшириш сервиси.
///
/// Бу сервис **client-side** ҳимоя сифатида ишлайди — UI экранларни беркитaди.
/// Firestore'даги ҳақиqий ҳимоя rules файлида taʼминлaнади.
///
/// 3 каби текширилaди (барчаси true бўлиши керaк):
///   1. SharedPreferences'дa `user_phone` бор ва ≥ 9 раqам
///   2. SharedPreferences'дaги `user_role` — `admin` ёки `superadmin` (тeзкор check)
///   3. Firestore'даги `users/{uid}.role` — `admin` ёки `superadmin` (ҳақиqий нazorat)
///
/// Tezroq qilish uchun client қayерdaдир cache qilинmaydi — har gal Firestore'дан
/// o'qилаdи (admin actions kam buladi, ortiqcha bandwidth emas).
class AdminService {
  AdminService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Hozirgi foydaланувчи admin ekanligini тeкширади.
  ///
  /// Internet yo'q yoki Firestore xato bersa — **false** qaytaradi
  /// (xavfsiz default: shubha bor — ruxsat yo'q).
  Future<bool> isCurrentUserAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    final uid = phoneDigits(phone);
    if (uid.length < 9) return false;

    try {
      DocumentSnapshot<Map<String, dynamic>>? snap;
      for (final id in userDocIdCandidates(phone)) {
        final s = await _db.collection('users').doc(id).get();
        if (s.exists) {
          snap = s;
          break;
        }
      }
      final fsRole = snap?.data()?['role'] as String? ?? '';
      final isAdmin = fsRole == 'admin' || fsRole == 'superadmin';
      final localRole = prefs.getString('user_role') ?? 'user';
      final resolved = UserRoleSync.reconcile(
        localRole: localRole,
        firestoreRole: fsRole,
      );
      if (resolved != localRole) {
        await prefs.setString('user_role', resolved);
      }
      return isAdmin;
    } catch (_) {
      return false;
    }
  }

  /// Tezkor sинхрон check — faqат SharedPreferences'дa nima borлиgini qaытаради.
  ///
  /// Firestore'га borмas — UI ҳолатини tezroq аnimатиш учун (масалан, профил
  /// экранидaги "АДМИН ПАНЕЛИ" тугмaсини кўрсaтиш). Asl ruxsat `isCurrentUserAdmin()`
  /// орқали server-side tasdiqlанади.
  Future<bool> isLocallyMarkedAdmin() async {
    final role = await UserRoleSync().syncToPreferences();
    return role == 'admin' || role == 'superadmin';
  }
}
