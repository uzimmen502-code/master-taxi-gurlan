import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/utils/formatters.dart';
import '../models/realty_listing.dart';

/// `realty_listings` — «Кўчмас мулк Кластери» базаси.
///
/// Ёзиш йўли `ev_station_repository.dart` билан бир хил нақшда: клиент
/// тўғридан-тўғри `create` қилмайди, `submitRealtyListing` callable
/// (Admin SDK) орқали — бепул лимит, ҳудуд тамғаси ва муддат серверда
/// ҳисобланади. Ўқиш эса оддий Firestore stream.
class RealtyRepository {
  RealtyRepository({FirebaseFirestore? db, FirebaseFunctions? functions})
      : _db = db ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  static const _uuid = Uuid();

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('realty_listings');

  String get _currentUserId =>
      canonicalPhoneId(FirebaseAuth.instance.currentUser?.phoneNumber ?? '');

  /// Битта TAB лентаси — ОДДИЙ / РЕКЛАМА / СРОЧНО.
  ///
  /// Муддати тугаганларни сервер ўчиргунча (`realtyExpirySweep`, кунига
  /// бир марта) лентада қолиб кетмасин деб клиентда ҳам фильтрланади.
  Stream<List<RealtyListing>> watchByTier(
    RealtyTier tier, {
    RealtyDeal? deal,
    int limit = 50,
  }) {
    return _col
        .where('status', isEqualTo: 'active')
        .where('tier', isEqualTo: tier.key)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => _live(snap.docs, deal: deal));
  }

  /// Харита учун — учала турдаги объект TAB'дан қатъи назар бирга
  /// кўринади (концепция, 7-бўлим: «Харита тури — умумий»).
  ///
  /// ⚠️ 1-босқичда ҲЕЧ КИМ чақирмайди: харита ахборот пакетлари билан
  /// бирга, 3-босқичда ёқилади (қаранг: `realty_screen.dart` изоҳи).
  Stream<List<RealtyListing>> watchForMap({
    RealtyDeal? deal,
    int limit = 300,
  }) {
    return _col
        .where('status', isEqualTo: 'active')
        .limit(limit)
        .snapshots()
        .map((snap) => _live(snap.docs, deal: deal));
  }

  /// Эганинг ўз объектлари — бепул лимитни кўрсатиш ва таҳрир учун.
  Stream<List<RealtyListing>> watchMine() {
    final uid = _currentUserId;
    if (uid.isEmpty) return Stream.value(const <RealtyListing>[]);
    return _col
        .where('ownerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(RealtyListing.fromDoc).toList());
  }

  /// Админ модерацияси — статус бўйича навбат.
  ///
  /// `null` берилса ҳамма ёзув (янгиси юқорида). Фойдаланувчи
  /// оқимларидан фарқли: муддати тугаганлар ҳам чиқади, чунки админ
  /// уларни кўра олиши керак.
  Stream<List<RealtyListing>> watchForModeration({
    String? status,
    int limit = 200,
  }) {
    Query<Map<String, dynamic>> q = _col;
    if (status != null) q = q.where('status', isEqualTo: status);
    return q
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(RealtyListing.fromDoc).toList());
  }

  Future<RealtyListing?> fetchById(String id) async {
    final snap = await _col.doc(id).get();
    if (!snap.exists) return null;
    return RealtyListing.fromDoc(snap);
  }

  List<RealtyListing> _live(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    RealtyDeal? deal,
  }) {
    final items = docs
        .map(RealtyListing.fromDoc)
        .where((r) => !r.isExpired)
        .where((r) => deal == null || r.deal == deal)
        .toList();
    // `watchForMap` серверда тартибламайди (индекссиз) — лентадагидек
    // янгиси юқорида турсин.
    items.sort((a, b) {
      final ax = a.createdAt, bx = b.createdAt;
      if (ax == null || bx == null) return 0;
      return bx.compareTo(ax);
    });
    return items;
  }

  /// Янги объект. Координата мажбурий — чақирувчи уни харитадан олади.
  ///
  /// Хатолар [RealtyException] сифатида қайтади: `free_limit_reached`,
  /// `location_required`, `daily_limit`, `tier_not_available`.
  Future<RealtySubmitResult> submitListing({
    required RealtyDeal deal,
    required RealtyTier tier,
    required String title,
    required String text,
    required double lat,
    required double lng,
    required RealtyContactMode contactMode,
    String priceText = '',
    String addressText = '',
    int? rooms,
    int? floor,
    int? totalFloors,
    num? areaM2,
    List<String> imageUrls = const [],
    String ownerName = '',
  }) async {
    try {
      final res = await _functions
          .httpsCallable(
            'submitRealtyListing',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          )
          .call({
        'idempotencyKey': _uuid.v4(),
        'deal': deal.key,
        'tier': tier.key,
        'title': title.trim(),
        'text': text.trim(),
        'lat': lat,
        'lng': lng,
        'contactMode': contactMode.key,
        if (priceText.trim().isNotEmpty) 'priceText': priceText.trim(),
        if (addressText.trim().isNotEmpty) 'addressText': addressText.trim(),
        if (rooms != null) 'rooms': rooms,
        if (floor != null) 'floor': floor,
        if (totalFloors != null) 'totalFloors': totalFloors,
        if (areaM2 != null) 'areaM2': areaM2,
        if (imageUrls.isNotEmpty) 'imageUrls': imageUrls,
        if (ownerName.trim().isNotEmpty) 'ownerName': ownerName.trim(),
      });
      final data = Map<String, dynamic>.from(res.data as Map? ?? const {});
      return RealtySubmitResult(
        listingId: (data['listingId'] ?? '') as String,
        status: (data['status'] ?? 'pending') as String,
        freeLeft: (data['freeLeft'] as num?)?.toInt() ?? 0,
      );
    } on FirebaseFunctionsException catch (e) {
      final details = e.details is Map
          ? Map<String, dynamic>.from(e.details as Map)
          : const <String, dynamic>{};
      throw RealtyException(
        (details['reason'] ?? e.message ?? e.code).toString(),
        details: details,
      );
    }
  }

  /// Мавжуд объектни таҳрирлаш — нарх тушиши кўчмас мулкда одатий ҳол.
  ///
  /// `tier` ва муддат бу ердан ўзгармайди (улар тўлов иши). Модерация
  /// ёқиқ бўлса эълон қайта текширувга тушади — қайтган `status` шуни
  /// айтади.
  Future<RealtySubmitResult> updateListing({
    required String listingId,
    required RealtyDeal deal,
    required String title,
    required String text,
    required double lat,
    required double lng,
    required RealtyContactMode contactMode,
    String priceText = '',
    String addressText = '',
    int? rooms,
    int? floor,
    int? totalFloors,
    num? areaM2,
    List<String> imageUrls = const [],
  }) async {
    try {
      final res = await _functions
          .httpsCallable(
            'updateRealtyListing',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          )
          .call({
        'listingId': listingId,
        'deal': deal.key,
        'title': title.trim(),
        'text': text.trim(),
        'lat': lat,
        'lng': lng,
        'contactMode': contactMode.key,
        'priceText': priceText.trim(),
        'addressText': addressText.trim(),
        'rooms': rooms,
        'floor': floor,
        'totalFloors': totalFloors,
        'areaM2': areaM2,
        'imageUrls': imageUrls,
      });
      final data = Map<String, dynamic>.from(res.data as Map? ?? const {});
      return RealtySubmitResult(
        listingId: (data['listingId'] ?? listingId) as String,
        status: (data['status'] ?? 'active') as String,
        freeLeft: 0,
      );
    } on FirebaseFunctionsException catch (e) {
      final details = e.details is Map
          ? Map<String, dynamic>.from(e.details as Map)
          : const <String, dynamic>{};
      throw RealtyException(
        (details['reason'] ?? e.message ?? e.code).toString(),
        details: details,
      );
    }
  }

  /// РЕКЛАМА ёки СРОЧНО сотиб олиш / узайтириш (AVA ҳамёнидан).
  ///
  /// Хатолар: `insufficient_balance` (`details.price`, `details.balance`),
  /// `not_owner`, `listing_blocked`, `bad_duration`.
  Future<RealtyPurchaseResult> purchaseTier({
    required String listingId,
    required RealtyTier tier,
    required int durationDays,
  }) async {
    try {
      final res = await _functions
          .httpsCallable(
            'purchaseRealtyTier',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          )
          .call({
        'idempotencyKey': _uuid.v4(),
        'listingId': listingId,
        'tier': tier.key,
        'durationDays': durationDays,
      });
      final data = Map<String, dynamic>.from(res.data as Map? ?? const {});
      return RealtyPurchaseResult(
        listingId: (data['listingId'] ?? listingId) as String,
        tier: RealtyTierX.parse(data['tier']),
        durationDays: (data['durationDays'] as num?)?.toInt() ?? durationDays,
        price: (data['price'] as num?)?.toInt() ?? 0,
        tierUntil: DateTime.fromMillisecondsSinceEpoch(
          (data['tierUntil'] as num?)?.toInt() ?? 0,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      final details = e.details is Map
          ? Map<String, dynamic>.from(e.details as Map)
          : const <String, dynamic>{};
      throw RealtyException(
        (details['reason'] ?? e.message ?? e.code).toString(),
        details: details,
      );
    }
  }

  /// Тариф жадвали: даража → {кун: нарх}. Админ панелдан таҳрирланади.
  ///
  /// Сервер жавоб бермаса бўш жадвал қайтади — чақирувчи «нарх
  /// юкланмади» деб кўрсатсин, ноль нархни эмас.
  Future<Map<RealtyTier, Map<int, int>>> loadPricing() async {
    try {
      final res = await _functions.httpsCallable('getRealtyPricing').call();
      final raw = Map<String, dynamic>.from(res.data as Map? ?? const {});
      final pricing = Map<String, dynamic>.from(
        raw['pricing'] as Map? ?? const {},
      );
      final out = <RealtyTier, Map<int, int>>{};
      for (final entry in pricing.entries) {
        final tier = RealtyTierX.parse(entry.key);
        final days = Map<String, dynamic>.from(entry.value as Map? ?? const {});
        final parsed = <int, int>{};
        for (final e in days.entries) {
          final k = int.tryParse(e.key);
          final v = (e.value as num?)?.toInt();
          if (k != null && v != null) parsed[k] = v;
        }
        if (parsed.isNotEmpty) out[tier] = parsed;
      }
      return out;
    } catch (e) {
      debugPrint('[RealtyRepository] loadPricing $e');
      return const {};
    }
  }

  /// Эга ўз объектини ўчиради («сотилди» ёки нотўғри киритилди).
  Future<void> deleteMine(String listingId) async {
    try {
      await _functions.httpsCallable('deleteRealtyListing').call({
        'listingId': listingId,
      });
    } on FirebaseFunctionsException catch (e) {
      throw RealtyException(e.message ?? e.code);
    }
  }
}

class RealtySubmitResult {
  const RealtySubmitResult({
    required this.listingId,
    required this.status,
    required this.freeLeft,
  });

  final String listingId;
  final String status;

  /// Эгада яна нечта бепул ОДДИЙ объект ўрни қолгани.
  final int freeLeft;

  bool get isLive => status == 'active';
}

/// `purchaseRealtyTier` муваффақиятли натижаси.
class RealtyPurchaseResult {
  const RealtyPurchaseResult({
    required this.listingId,
    required this.tier,
    required this.durationDays,
    required this.price,
    required this.tierUntil,
  });

  final String listingId;
  final RealtyTier tier;
  final int durationDays;
  final int price;
  final DateTime tierUntil;
}

class RealtyException implements Exception {
  const RealtyException(this.code, {this.details = const {}});

  final String code;
  final Map<String, dynamic> details;

  bool get isFreeLimit => code == 'free_limit_reached';

  @override
  String toString() => 'RealtyException($code)';
}
