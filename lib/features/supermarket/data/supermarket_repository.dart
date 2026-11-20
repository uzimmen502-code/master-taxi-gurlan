import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../domain/sm_access.dart';
import '../domain/sm_cart.dart';
import '../domain/sm_offer.dart';
import '../domain/sm_qty.dart';
import '../domain/sm_taxonomy.dart';

/// Супермаркет сервер чақирувлари учун хато (UI калити + ички код, 25-банд).
class SmCallError implements Exception {
  const SmCallError(this.key, this.code);

  /// lang калити (`sm_err_*`).
  final String key;

  /// Ички диагностика коди (логга).
  final String code;

  @override
  String toString() => 'SmCallError($code)';
}

/// Супермаркет маълумот манбаи. Тестда [SupermarketApi] алмаштирилади (сохта, тармоқсиз).
abstract class SupermarketApi {
  Future<SmTaxonomy> loadTaxonomy();
  Future<List<SmOffer>> loadOffers(SmTaxonomy taxonomy);
  Future<SmAccess> getAccess();
  Future<SmPlaceResult> placeOrder(Map<String, dynamic> payload);
}

class FirebaseSupermarketApi implements SupermarketApi {
  FirebaseSupermarketApi({FirebaseFirestore? db, FirebaseFunctions? functions})
      : _db = db ?? FirebaseFirestore.instance,
        _fns = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _fns;

  @override
  Future<SmTaxonomy> loadTaxonomy() async {
    final doc = await _db.collection('taxonomy').doc('supermarket').get();
    return SmTaxonomy.fromMap(doc.data());
  }

  /// Фақат супермаркет таклифлари (`smGroupId` бор): битта майдон сўрови — автоматик индекс,
  /// бутун каталог ўқилмайди (36/37-банд).
  @override
  Future<List<SmOffer>> loadOffers(SmTaxonomy taxonomy) async {
    final snap = await _db
        .collection('platform_products')
        .where('smGroupId', isGreaterThan: '')
        .limit(2000)
        .get();
    return [
      for (final d in snap.docs)
        SmOffer.fromMap(d.id, d.data(), group: taxonomy.group((d.data()['smGroupId'] as String?) ?? '')),
    ];
  }

  Future<Object?> _call(String name, Map<String, dynamic> data) async {
    try {
      final res = await _fns.httpsCallable(name).call<Object?>(data);
      return res.data;
    } on FirebaseFunctionsException catch (e) {
      final key = smErrorKey(grpcCode: e.code, details: e.details);
      debugPrint('[Supermarket] $name failed code=${e.code} details=${e.details is Map ? (e.details as Map)['code'] : ''}');
      throw SmCallError(key, e.code);
    }
  }

  @override
  Future<SmAccess> getAccess() async => SmAccess.fromMap(await _call('getSupermarketAccess', const {}));

  @override
  Future<SmPlaceResult> placeOrder(Map<String, dynamic> payload) async =>
      SmPlaceResult.fromMap(await _call('placeSupermarketOrder', payload));
}

/// Модул кўриниши учун `getSupermarketAccess` кеши (бош саҳифа ҳар қайта қурилганда чақирилмасин,
/// 37-банд). Хато — «кўрсатилмайди» (хавфсиз томон).
class SupermarketAccessCache {
  SupermarketAccessCache._();

  static const ttl = Duration(minutes: 5);
  static SmAccess? _value;
  static DateTime? _at;
  static Future<SmAccess>? _inflight;

  static SmAccess? get cached => _value;

  static Future<SmAccess> get(SupermarketApi api, {bool force = false}) {
    final at = _at;
    if (!force && _value != null && at != null && DateTime.now().difference(at) < ttl) {
      return Future.value(_value);
    }
    return _inflight ??= () async {
      try {
        final v = await api.getAccess();
        _value = v;
        _at = DateTime.now();
        return v;
      } catch (e) {
        debugPrint('[Supermarket] SUPERMARKET_ACCESS_FAILED: $e');
        return SmAccess.denied;
      } finally {
        _inflight = null;
      }
    }();
  }

  @visibleForTesting
  static void resetForTest([SmAccess? value]) {
    _value = value;
    _at = value == null ? null : DateTime.now();
    _inflight = null;
  }
}

/// Саватни қурилмада сақлаш (илова қайта очилганда ҳам), фойдаланувчи телефони бўйича ажратилган
/// (мавжуд `PlatformCartStore` қолипи).
class SmCartStore {
  static const _prefix = 'sm_cart_v1_';

  String keyFor(String phone) {
    final d = phoneDigits(phone);
    return '$_prefix${d.isEmpty ? 'guest' : d}';
  }

  Future<String> _key(SharedPreferences prefs) async => keyFor(prefs.getString('user_phone') ?? '');

  Future<SmCart> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(await _key(prefs));
      if (raw == null || raw.isEmpty) return SmCart.empty;
      return SmCart.fromJson(jsonDecode(raw));
    } catch (e) {
      debugPrint('[SmCartStore] load: $e');
      return SmCart.empty;
    }
  }

  Future<void> save(SmCart cart) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = await _key(prefs);
      if (cart.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, jsonEncode(cart.toJson()));
      }
    } catch (e) {
      debugPrint('[SmCartStore] save: $e');
    }
  }
}

/// Буюртма тўлови — `placeSupermarketOrder` payload (шартнома). Миқдор серверга оддий сон (1.5).
Map<String, dynamic> smOrderPayload({
  required String clientRequestId,
  required SmCart cart,
  required Map<String, dynamic> address,
  required String slotId,
  required String day,
}) =>
    {
      'clientRequestId': clientRequestId,
      'items': [
        for (final l in cart.lines) {'productId': l.productId, 'qty': smFromMilli(l.qtyMilli)},
      ],
      'address': address,
      'slotId': slotId,
      'day': day,
    };
