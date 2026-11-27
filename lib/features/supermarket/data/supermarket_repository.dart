import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../domain/sm_access.dart';
import '../domain/sm_cart.dart';
import '../domain/sm_holiday.dart' show SmGift;
import '../domain/sm_offer.dart';
import '../domain/sm_qty.dart';
import '../domain/sm_shortage.dart';
import '../domain/sm_taxonomy.dart';

export '../domain/sm_taxonomy.dart' show smNames;

/// Супермаркет сервер чақирувлари учун хато (UI калити + ички код, 25-банд).
class SmCallError implements Exception {
  const SmCallError(this.key, this.code, {this.messages = const {}, this.details = const {}});

  /// lang калити (`sm_err_*`) — захира матн.
  final String key;

  /// Ички диагностика коди (логга).
  final String code;

  /// Сервер берган дўстона матн (`details.messages`, 3 тил) — бўлса шу кўрсатилади.
  final Map<String, String> messages;

  /// Хом `details` (масалан INSUFFICIENT_FUNDS: `required`, `balance`; QTY_STEP_INVALID: `step`, `maxQty`).
  final Map<String, dynamic> details;

  @override
  String toString() => 'SmCallError($code)';
}

/// Супермаркет маълумот манбаи. Тестда [SupermarketApi] алмаштирилади (сохта, тармоқсиз).
abstract class SupermarketApi {
  Future<SmTaxonomy> loadTaxonomy();
  Future<List<SmOffer>> loadOffers(SmTaxonomy taxonomy);
  /// [districtId] берилса — шу туман учун (расмийлаштириш); йўқ — профиль тумани (бош саҳифа).
  /// [withDates] — байрам/совға: бугундан +14 кунгача `dateSlots` ҳам (сервер 5eb77906).
  Future<SmAccess> getAccess({String? districtId, bool withDates = false});
  Future<SmPlaceResult> placeOrder(Map<String, dynamic> payload);

  /// `respondSupermarketShortage` → `{ok, refund, debit, total, duplicate?}`. Хато — [SmCallError].
  Future<SmShortageResult> respondShortage(Map<String, dynamic> payload);
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
      final details = e.details is Map ? e.details as Map : const {};
      final code = (details['code'] ?? e.code).toString();
      debugPrint('[Supermarket] $name failed grpc=${e.code} code=$code');
      throw SmCallError(key, code,
          messages: smNames(details['messages']),
          details: {for (final e in details.entries) if (e.key is String) e.key as String: e.value});
    }
  }

  @override
  Future<SmAccess> getAccess({String? districtId, bool withDates = false}) async => SmAccess.fromMap(await _call(
        'getSupermarketAccess',
        {
          if (districtId != null && districtId.isNotEmpty) 'districtId': districtId,
          if (withDates) 'withDates': true,
        },
      ));

  @override
  Future<SmPlaceResult> placeOrder(Map<String, dynamic> payload) async =>
      SmPlaceResult.fromMap(await _call('placeSupermarketOrder', payload));

  @override
  Future<SmShortageResult> respondShortage(Map<String, dynamic> payload) async =>
      SmShortageResult.fromMap(await _call('respondSupermarketShortage', payload));
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

/// Буюртма манбалари — сервер `ORDER_ORIGINS` (supermarket.js) билан бир хил рўйхат.
const smOriginCatalog = 'catalog';
const smOriginQuick = 'quick';
const smOriginWeekly = 'weekly';
const smOriginReorder = 'reorder';
const smOrigins = [smOriginCatalog, smOriginQuick, smOriginWeekly, smOriginReorder];

/// «Байрам саватчаси» буюртмаси (сервер 5eb77906 `ORDER_ORIGINS`) — фақат [smHolidayOrderPayload] орқали.
const smOriginHoliday = 'holiday';

/// Буюртма тўлови — `placeSupermarketOrder` payload (шартнома). Миқдор серверга оддий сон (1.5).
Map<String, dynamic> smOrderPayload({
  required String clientRequestId,
  required SmCart cart,
  required Map<String, dynamic> address,
  // Эга 2026-11-28: вақт оралиғи йўқ — имкон қадар тез (сервер slotId'сиз = бугун). Эски шакл учун ихтиёрий.
  String slotId = '',
  String day = '',
  String origin = smOriginCatalog,
}) =>
    {
      'clientRequestId': clientRequestId,
      'items': [
        for (final l in cart.lines) {'productId': l.productId, 'qty': smFromMilli(l.qtyMilli)},
      ],
      'address': address,
      if (slotId.isNotEmpty) 'slotId': slotId,
      if (slotId.isNotEmpty && day.isNotEmpty) 'day': day,
      'origin': smOrigins.contains(origin) ? origin : smOriginCatalog,
      // Эга 2026-11-27: бонус ҲАММА супермаркет буюртмасида — қанча қўлланишини сервер ҳал қилади.
      'useIncentive': true,
    };

/// Байрам/совға буюртмаси (сервер 5eb77906): `day` ўрнига `deliveryDate`, `origin: 'holiday'`, ихтиёрий `gift`,
/// `occasionId`/`basketId`, `useIncentive: true` (сервер фақат супермаркет бонусини қўллайди, ҳамёндан қолгани).
Map<String, dynamic> smHolidayOrderPayload({
  required String clientRequestId,
  required SmCart cart,
  required Map<String, dynamic> address,
  String slotId = '',
  required String deliveryDate,
  SmGift? gift,
  String occasionId = '',
  String basketId = '',
  String origin = smOriginHoliday,
}) =>
    {
      'clientRequestId': clientRequestId,
      'items': [
        for (final l in cart.lines) {'productId': l.productId, 'qty': smFromMilli(l.qtyMilli)},
      ],
      'address': address,
      if (slotId.isNotEmpty) 'slotId': slotId,
      'deliveryDate': deliveryDate,
      // Эга 2026-11-28: ҳафталик саватчадан — 'weekly' (сервер deliveryDate'ни ҳар қандай манбада қабул қилади).
      'origin': origin == smOriginWeekly ? smOriginWeekly : smOriginHoliday,
      'useIncentive': true,
      if (gift != null) 'gift': gift.toMap(),
      if (occasionId.isNotEmpty) 'occasionId': occasionId,
      if (basketId.isNotEmpty) 'basketId': basketId,
    };
