import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../domain/sm_access.dart';
import '../domain/sm_holiday.dart';
import 'supermarket_repository.dart';

/// «Байрам саватчаси» маълумот манбаи (сервер 5eb77906, `functions/holiday.js`). Тестда сохта.
abstract class HolidayApi {
  /// `getHolidayCatalog()` — фойдаланувчига кўринадиган байрамлар ва саватлар (internal тестерлар ҳам).
  Future<HolidayCatalog> loadCatalog();

  /// `buildHolidayBasket` → қаторлар + тизим ўзгаришлари. Хато — [SmCallError].
  Future<HolidayBuildResult> build({required String basketId, int? guests, int? budget});

  /// `claimRelativesBonus()` → хом жавоб (идемпотент; шартлар бажарилган бўлса бонус беради).
  Future<Object?> claimRelativesBonus();
}

class FirebaseHolidayApi implements HolidayApi {
  FirebaseHolidayApi({FirebaseFunctions? functions}) : _fns = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _fns;

  Future<Object?> _call(String name, Map<String, dynamic> data) async {
    try {
      final res = await _fns.httpsCallable(name).call<Object?>(data);
      return res.data;
    } on FirebaseFunctionsException catch (e) {
      final details = e.details is Map ? e.details as Map : const {};
      final code = (details['code'] ?? e.code).toString();
      debugPrint('[Holiday] $name failed grpc=${e.code} code=$code');
      throw SmCallError(smErrorKey(grpcCode: e.code, details: e.details), code, messages: smNames(details['messages']));
    }
  }

  @override
  Future<HolidayCatalog> loadCatalog() async => HolidayCatalog.fromMap(await _call('getHolidayCatalog', const {}));

  @override
  Future<HolidayBuildResult> build({required String basketId, int? guests, int? budget}) async =>
      HolidayBuildResult.fromMap(await _call('buildHolidayBasket', {
        'basketId': basketId,
        if (guests != null) 'guests': guests,
        if (budget != null) 'budget': budget,
      }));

  @override
  Future<Object?> claimRelativesBonus() => _call('claimRelativesBonus', const {});
}

/// Бош саҳифа / қариндошлар / байрам экрани учун каталог кеши (37-банд): 10 дақиқа. Хато — бўш (хавфсиз томон).
class HolidayCatalogCache {
  HolidayCatalogCache._();

  static const ttl = Duration(minutes: 10);
  static HolidayCatalog? _value;
  static DateTime? _at;
  static Future<HolidayCatalog>? _inflight;

  static HolidayCatalog? get cached => _value;

  static Future<HolidayCatalog> get(HolidayApi api, {bool force = false}) {
    final at = _at;
    if (!force && _value != null && at != null && DateTime.now().difference(at) < ttl) return Future.value(_value);
    return _inflight ??= () async {
      try {
        final v = await api.loadCatalog();
        _value = v;
        _at = DateTime.now();
        return v;
      } catch (e) {
        debugPrint('[Holiday] HOLIDAY_CATALOG_FAILED: $e');
        return HolidayCatalog.empty;
      } finally {
        _inflight = null;
      }
    }();
  }

  @visibleForTesting
  static void resetForTest([HolidayCatalog? value]) {
    _value = value;
    _at = value == null ? null : DateTime.now();
    _inflight = null;
  }
}

/// Саватча карточкаси/тугмаси учун: супермаркет рухсати + сервер каталоги (иккаласи ҳам кешдан). Саватча
/// (супермаркет) мақсадли байрамлар — рухсат ШАРТ.
Future<bool> holidayAvailable({required bool smOpenable, SupermarketApi? smApi, HolidayApi? api}) async {
  if (!smOpenable) return false;
  final SmAccess access = await SupermarketAccessCache.get(smApi ?? FirebaseSupermarketApi());
  if (!access.allowed) return false;
  final cat = await HolidayCatalogCache.get(api ?? FirebaseHolidayApi());
  return holidayCardVisible(smOpenable: smOpenable, smAllowed: access.allowed, occasions: cat.occasions);
}

/// Бозор мақсадли фаол байрам (Қурбон ҳайит → Мол бозори) — супермаркет рухсатисиз (эга 2026-11-28; сервер
/// каталоги уни супермаркет ёпиқ бўлса ҳам қайтаради). Йўқ — `null`. Каталог кешдан (10 дақиқа).
Future<HolidayOccasion?> holidayMarketAvailable({HolidayApi? api, DateTime? today}) async {
  final cat = await HolidayCatalogCache.get(api ?? FirebaseHolidayApi());
  return holidayMarketOccasion(cat.occasions, today ?? smTashkentDate());
}
