import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/formatters.dart';

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

    // Tezkor pre-check — local prefs'da admin emas bo'lsa, Firestore'ga
    // bormaymiz (UX uchun).
    final localRole = prefs.getString('user_role') ?? 'user';
    if (localRole != 'admin' && localRole != 'superadmin') return false;

    try {
      final snap = await _db.collection('users').doc(uid).get();
      final fsRole = snap.data()?['role'] as String? ?? '';
      return fsRole == 'admin' || fsRole == 'superadmin';
    } catch (_) {
      // Internet yo'q yoki rules denied — xavfsiz default.
      return false;
    }
  }

  /// Tezkor sинхрон check — faqат SharedPreferences'дa nima borлиgini qaытаради.
  ///
  /// Firestore'га borмas — UI ҳолатини tezroq аnimатиш учун (масалан, профил
  /// экранидaги "АДМИН ПАНЕЛИ" тугмaсини кўрсaтиш). Asl ruxsat `isCurrentUserAdmin()`
  /// орқали server-side tasdiqlанади.
  Future<bool> isLocallyMarkedAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role') ?? 'user';
    return role == 'admin' || role == 'superadmin';
  }
}
