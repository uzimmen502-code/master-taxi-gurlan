// Moderatsiya rejimlari (AVTO / QO'LDA) — admin web uchun YAGONA kirish nuqtasi (ega 2026-11-28, audit C-1).
//
// Server manbasi: functions/moderation_modes.js
//   • `adminGetModerationModes()` → { modes: [{ mode, field, defaultOn, enabled, stored }] } — registr (maydon nomi va
//     standart qiymat FAQAT serverda; klient ularni takrorlamaydi);
//   • `adminSetModerationMode({ mode, enabled, reason? })` → `settings/app.<field>` + `admin_audit` (41-band).
// Firestore rules `settings/app` dagi `*AutoApprove` maydonlarini klient to'g'ridan-to'g'ri yozishidan yopadi.
//
// Jonli ko'rinish: `settings/app` oqimi + server bergan `field`/`defaultOn` (boshqa admin o'zgartirsa ham yangilanadi).

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Server registridagi rejim nomlari (`MODERATION_MODES` kalitlari).
abstract final class ModerationMode {
  static const dating = 'dating';
  static const market = 'market';
  static const jobs = 'jobs';
  static const tv = 'tv';
  static const shopItem = 'shopItem';
  static const wholesaleProduct = 'wholesaleProduct';
  static const wholesaleSeller = 'wholesaleSeller';
  static const realty = 'realty';
  static const producerVerify = 'producerVerify';
  static const supermarketPartner = 'supermarketPartner';
}

/// Server qaytargan bitta rejim tavsifi.
class ModerationModeInfo {
  const ModerationModeInfo({required this.mode, required this.field, required this.defaultOn});

  final String mode;
  final String field;
  final bool defaultOn;

  /// Server `isModeAuto` bilan bir xil: defaultOn → faqat aniq `false` o'chiradi; aks holda faqat aniq `true` yoqadi.
  bool effective(Map<String, dynamic>? settings) {
    final v = settings?[field];
    return defaultOn ? v != false : v == true;
  }

  static ModerationModeInfo? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final mode = raw['mode'];
    final field = raw['field'];
    if (mode is! String || field is! String || mode.isEmpty || field.isEmpty) return null;
    return ModerationModeInfo(mode: mode, field: field, defaultOn: raw['defaultOn'] == true);
  }
}

class AdminModerationModesService {
  AdminModerationModesService({FirebaseFunctions? functions, FirebaseFirestore? firestore})
      : _functionsOverride = functions,
        _dbOverride = firestore;

  final FirebaseFunctions? _functionsOverride;
  final FirebaseFirestore? _dbOverride;
  FirebaseFunctions get _functions => _functionsOverride ?? FirebaseFunctions.instance;
  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  Future<Map<String, ModerationModeInfo>>? _registry;

  /// Registr bir marta olinadi (xato bo'lsa keyingi chaqiruvda qayta urinadi).
  Future<Map<String, ModerationModeInfo>> registry() {
    final cached = _registry;
    if (cached != null) return cached;
    final f = _fetchRegistry();
    _registry = f;
    f.catchError((Object _) {
      _registry = null;
      return const <String, ModerationModeInfo>{};
    });
    return f;
  }

  Future<Map<String, ModerationModeInfo>> _fetchRegistry() async {
    final res = await _functions.httpsCallable('adminGetModerationModes').call<Object?>(const <String, Object?>{});
    final data = res.data;
    final list = data is Map ? data['modes'] : null;
    final out = <String, ModerationModeInfo>{};
    if (list is List) {
      for (final raw in list) {
        final info = ModerationModeInfo.fromMap(raw);
        if (info != null) out[info.mode] = info;
      }
    }
    return out;
  }

  /// Rejimning SAMARALI qiymati oqimi. Registrda yo'q rejim — xato (UI qizil xabar ko'rsatadi).
  Stream<bool> watch(String mode) async* {
    final reg = await registry();
    final info = reg[mode];
    if (info == null) throw StateError('MODE_UNKNOWN');
    yield* _db.collection('settings').doc('app').snapshots().map((s) => info.effective(s.data()));
  }

  /// Server: `adminSetModerationMode` (audit). Bir xil qiymat — server noop qiladi.
  Future<void> set(String mode, bool enabled, {String? reason}) async {
    await _functions.httpsCallable('adminSetModerationMode').call<Object?>({
      'mode': mode,
      'enabled': enabled,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
  }
}
