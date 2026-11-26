import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';

/// Саватча сарлавҳаси учун туғилган кунлар (эга 2026-11-28): ўзи — `users.birthDate` (қурилмадаги нусха
/// `user_birth_date`; бўлмаса «Мен» ёзуви), турмуш ўртоғи — «Мен» ёзувининг `spouseId` → ўша одамнинг `birthDate`.
typedef SmBasketBirthdays = ({DateTime? own, DateTime? spouse});
typedef SmBasketBirthdaysLoader = Future<SmBasketBirthdays> Function();

SmBasketBirthdays? _cache;

@visibleForTesting
void resetSmBasketBirthdaysCache() => _cache = null;

/// Сессияда бир марта: ≤ 2 ўқиш (`isSelf == true` limit 1 + турмуш ўртоғи ҳужжати), 37-банд. Хато — сана йўқ
/// (оддий сарлавҳа).
Future<SmBasketBirthdays> loadSmBasketBirthdays({FirebaseFirestore? db}) async {
  final cached = _cache;
  if (cached != null) return cached;
  DateTime? own;
  DateTime? spouse;
  try {
    final prefs = await SharedPreferences.getInstance();
    own = parseBirthDate(prefs.getString('user_birth_date') ?? '');
    final phone = canonicalPhoneId(prefs.getString('user_phone') ?? '');
    if (phone.length >= 12) {
      final people = (db ?? FirebaseFirestore.instance).collection('relatives').doc(phone).collection('people');
      final self = await people.where('isSelf', isEqualTo: true).limit(1).get();
      if (self.docs.isNotEmpty) {
        final d = self.docs.first.data();
        own ??= (d['birthDate'] as Timestamp?)?.toDate();
        final sid = d['spouseId'];
        if (sid is String && sid.trim().isNotEmpty) {
          final sp = await people.doc(sid.trim()).get();
          spouse = (sp.data()?['birthDate'] as Timestamp?)?.toDate();
        }
      }
    }
  } catch (e) {
    debugPrint('[Supermarket] SM_BASKET_BIRTHDAYS_FAILED: $e');
  }
  return _cache = (own: own, spouse: spouse);
}
