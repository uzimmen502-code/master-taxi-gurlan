import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/formatters.dart';
import '../../utils/locale_utils.dart';

/// Ilova tilini `users/{id}.appLang` ga yozadi (`uz_Cyrl` / `uz_Latn` / `ru`).
///
/// Sabab: server push/xabar matnlarini foydalanuvchi tilida yozadi
/// (`functions/notif_i18n.js`) — til faqat qurilmada saqlanardi. Maydon
/// yo'q (eski ilova) bo'lsa server `uz_Cyrl` ishlatadi. Xato bo'lsa jim
/// (til sinxroni ilovani to'xtatmaydi); `role`/hamyon maydonlariga tegmaydi.
class UserLangSync {
  UserLangSync._();

  /// Maydon qiymati — `assets/lang` fayl nomi bilan bir xil kod.
  static String code(Locale locale) => LocaleUtils.contentLangCode(locale);

  static Future<void> push([Locale? locale, FirebaseFirestore? db]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone') ?? '';
      if (phoneDigits(phone).length < 9) return;
      final lang = code(locale ?? await LocaleUtils.effectiveLocale());
      await (db ?? FirebaseFirestore.instance)
          .collection('users')
          .doc(canonicalPhoneId(phone))
          .set({'appLang': lang}, SetOptions(merge: true));
    } catch (_) {}
  }
}
