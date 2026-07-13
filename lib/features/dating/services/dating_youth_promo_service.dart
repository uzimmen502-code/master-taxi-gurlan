import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/offline_l10n.dart';
import '../../../core/utils/formatters.dart';
import '../../../services/notification_delivery.dart';

/// Рўйхатдаги ёши 18–23 бўлган фойдаланувчига иловага кирганда
/// танишув промо push (ротатсия, 3 тил).
class DatingYouthPromoService {
  DatingYouthPromoService._();

  static const _prefBirth = 'user_birth_date';
  static const _prefIdx = 'dating_youth_promo_idx';
  static const _prefLastMs = 'dating_youth_promo_last_ms';
  static const _debounceMs = 4000;
  static const _messageCount = 10;
  static const minAge = 18;
  static const maxAge = 23;

  /// Илова очилганда / foreground’га қайтганда чақирилади.
  static Future<void> maybeShowOnAppOpen() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = phoneDigits(prefs.getString('user_phone') ?? '');
      if (phone.length < 9) return;

      final role = prefs.getString('user_role') ?? 'user';
      if (role == 'driver' ||
          role == 'courier' ||
          role == 'admin' ||
          role == 'superadmin') {
        return;
      }

      var birth = (prefs.getString(_prefBirth) ?? '').trim();
      if (birth.isEmpty) {
        birth = await _loadBirthFromFirestore(phone);
        if (birth.isNotEmpty) {
          await prefs.setString(_prefBirth, birth);
        }
      }
      final age = ageFromBirthDate(birth);
      if (age == null || age < minAge || age > maxAge) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      final last = prefs.getInt(_prefLastMs) ?? 0;
      if (now - last < _debounceMs) return;
      await prefs.setInt(_prefLastMs, now);

      final idx = prefs.getInt(_prefIdx) ?? 0;
      final n = (idx % _messageCount) + 1;
      await prefs.setInt(_prefIdx, idx + 1);

      final title = await OfflineL10n.tr('dating_youth_promo_title');
      final body = await OfflineL10n.tr('dating_youth_promo_$n');
      await NotificationDelivery.show(
        title: title,
        body: body,
        type: 'dating_youth_promo',
        navigationData: const {'screen': 'dating'},
      );
    } catch (_) {}
  }

  static Future<String> _loadBirthFromFirestore(String uid) async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      return ((snap.data()?['birthDate'] ?? '') as String).trim();
    } catch (_) {
      return '';
    }
  }
}
