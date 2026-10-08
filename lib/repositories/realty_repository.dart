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

  /// Пул ишлайдиган чақирувлар учун кутиш вақти — стандарт 10 сония
  /// транзакция ва ҳамён ёзуви учун қисқа.
  static const _payTimeout = Duration(seconds: 30);

  /// Callable чақируви ва хатони [RealtyException] га айлантириш.
  ///
  /// Бу ҳелпер борлигининг сабаби: сервер хатони `details.reason` да
  /// қайтаради (`functions/realty.js` даги `fail()`), шунинг учун ҳар
  /// бир чақирувда бир хил «details'ни очиб, reason'ни олиб, қайта
  /// отиш» блоки керак бўлади. Аввал у ўн марта сўзма-сўз
  /// такрорланган эди — янги чақирув қўшганда уни эсдан чиқариш осон,
  /// ва ўша чақирувда илова хато сабабини кўрмай қоларди.
  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> payload, {
    Duration? timeout,
  }) async {
    try {
      final res = await _functions
          .httpsCallable(
            name,
            options:
                timeout == null ? null : HttpsCallableOptions(timeout: timeout),
          )
          .call(payload);
      return Map<String, dynamic>.from(res.data as Map? ?? const {});
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

  /// Фақат ЎҚИШ учун чақирув: хато бўлса бўш жадвал.
  ///
  /// Нархлар ва ҳисоблагичлар шу йўл билан олинади — сервер жавоб
  /// бермаса, чақирувчи «нарх юкланмади» деб кўрсатсин, ноль нархни
  /// эмас ва хато экранини ҳам эмас.
  Future<Map<String, dynamic>> _callOrEmpty(String name) async {
    try {
      return await _call(name, const {});
    } catch (e) {
      debugPrint('[RealtyRepository] $name $e');
      return const {};
    }
  }

  /// `{"5": 30000}` → `{5: 30000}`. Нотўғри калит/қиймат тушиб қолади.
  static Map<int, int> _intMap(Object? raw) {
    final src = Map<String, dynamic>.from(raw as Map? ?? const {});
    final out = <int, int>{};
    for (final e in src.entries) {
      final k = int.tryParse(e.key);
      final v = (e.value as num?)?.toInt();
      if (k != null && v != null) out[k] = v;
    }
    return out;
  }

  /// Фаол эълонлар оқими — лента, харита ва бош саҳифа учун битта жой.
  ///
  /// Учала жойда сўров шакли бир хил эди: `status == active`, ихтиёрий
  /// [tier] ёки [districtId], ва `createdAt` бўйича тартиб. Учта нусха
  /// ўрнига битта метод — чегара ёки тартиб ўзгарса, у ҳамма жойда
  /// бирга ўзгаради.
  ///
  /// `orderBy` МАЖБУРИЙ (2026-09-29): усиз Firestore лимитга тушган
  /// ҳужжатларни ихтиёрий тартибда танлар эди — 300 тадан ошганда
  /// харитада «энг янгилари» эмас, тасодифий 300 таси кўринарди.
  ///
  /// Керакли композит индекслар мавжуд: `status+createdAt`,
  /// `status+tier+createdAt` ва `status+districtId+createdAt`.
  Stream<List<RealtyListing>> _watchActive({
    RealtyTier? tier,
    RealtyDeal? deal,
    String districtId = '',
    required int limit,
  }) {
    final id = districtId.trim();
    Query<Map<String, dynamic>> q = _col.where('status', isEqualTo: 'active');
    if (tier != null) q = q.where('tier', isEqualTo: tier.key);
    if (id.isNotEmpty) q = q.where('districtId', isEqualTo: id);
    return q
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => _live(snap.docs, deal: deal));
  }

  /// Битта TAB лентаси — ОДДИЙ / РЕКЛАМА / СРОЧНО.
  ///
  /// Муддати тугаганларни сервер ўчиргунча (`realtyExpirySweep`, кунига
  /// бир марта) лентада қолиб кетмасин деб клиентда ҳам фильтрланади.
  Stream<List<RealtyListing>> watchByTier(
    RealtyTier tier, {
    RealtyDeal? deal,
    int limit = 50,
  }) =>
      _watchActive(tier: tier, deal: deal, limit: limit);

  /// Харита учун — учала даража TAB'дан қатъи назар бирга кўринади
  /// (концепция, 7-бўлим: «Харита тури — умумий»).
  ///
  /// [districtId] берилса фақат ўша туман — бу 300 талик чегарага
  /// тиқилиб қолишдан ҳам сақлайди.
  Stream<List<RealtyListing>> watchForMap({
    RealtyDeal? deal,
    String districtId = '',
    int limit = 300,
  }) =>
      _watchActive(deal: deal, districtId: districtId, limit: limit);

  /// Бош саҳифадаги «Кўчмас мулк» бўлими.
  ///
  /// Бош саҳифа бўлимлари ТУМАН бўйича филтрланади (`jobs_repository`
  /// даги `watchForHome` билан бир хил қоида) — тўлиқ доскадан фарқи
  /// шу. [districtId] бўш бўлса филтр қўлланмайди.
  ///
  /// Даража аҳамиятсиз: бош саҳифада учала TAB аралаш кўринади,
  /// янгиси юқорида.
  Stream<List<RealtyListing>> watchForHome({
    required String districtId,
    int limit = 10,
  }) =>
      _watchActive(districtId: districtId, limit: limit);

  /// Эганинг очиқ ҳужжатдаги калити (`users/{uid}.realtyOwnerKey`).
  ///
  /// Телефон очиқ эълонда сақланмагани учун ўз объектларини шу калит
  /// бўйича топамиз. Калит биринчи эълон яратилганда серверда пайдо
  /// бўлади — унгача бўш бўлиши нормал.
  Future<String> myOwnerKey() async {
    final cached = _ownerKeyCache;
    if (cached != null) return cached;
    final uid = _currentUserId;
    if (uid.isEmpty) return '';
    try {
      final snap = await _db.collection('users').doc(uid).get();
      final key = ((snap.data() ?? const {})['realtyOwnerKey'] ?? '') as String;
      if (key.isNotEmpty) _ownerKeyCache = key;
      return key;
    } catch (e) {
      debugPrint('[RealtyRepository] myOwnerKey $e');
      return '';
    }
  }

  String? _ownerKeyCache;

  /// Жорий фойдаланувчининг рақами — AVAGram клиплари шу бўйича
  /// сақланади (`tv_clips.ownerPhone`). Қиймат аллақачон
  /// `canonicalPhoneId` дан ўтган.
  String get myOwnerPhone => _currentUserId;

  /// Эганинг ўз объектлари — бепул лимитни кўрсатиш ва таҳрир учун.
  Stream<List<RealtyListing>> watchMine() {
    return Stream.fromFuture(myOwnerKey()).asyncExpand((key) {
      if (key.isEmpty) return Stream.value(const <RealtyListing>[]);
      return _col
          .where('ownerKey', isEqualTo: key)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snap) => snap.docs.map(RealtyListing.fromDoc).toList());
    });
  }

  /// Аниқ координата ва алоқа — ПУЛЛИК ахборот.
  ///
  /// Рухсат бўлмаса (пакетдан очилмаган) `null` қайтади. Бу хато эмас —
  /// қоида шундай ишлайди, шунинг учун лог ҳам ёзилмайди.
  Future<RealtyDetail?> fetchDetail(String listingId) async {
    try {
      final snap =
          await _col.doc(listingId).collection('private').doc('detail').get();
      if (!snap.exists) return null;
      return RealtyDetail.fromMap(snap.data() ?? const {});
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') {
        debugPrint('[RealtyRepository] fetchDetail ${e.code}');
      }
      return null;
    }
  }

  /// AVA риэлторлик хизматининг ЖОРИЙ рақами.
  ///
  /// Рақам эълон ёзувида сақланмайди (эга қарори, 2026-10-02) — акс
  /// ҳолда созламадаги рақам ўзгарганда эски эълонлар эски рақам билан
  /// қолиб кетарди. `settings/app` клиентга очиқ (`firestore.rules`),
  /// шунинг учун callable керак эмас.
  ///
  /// Бўш қайтса — чақирувчи эганинг ўз рақамини кўрсатади.
  Future<String> fetchAgentPhone() async {
    final cached = _agentPhoneCache;
    if (cached != null) return cached;
    try {
      final snap = await _db.collection('settings').doc('app').get();
      final raw = '${(snap.data() ?? const {})['realtyAgentPhone'] ?? ''}';
      final phone = raw.replaceAll(RegExp(r'\D'), '');
      _agentPhoneCache = phone;
      return phone;
    } catch (e) {
      debugPrint('[RealtyRepository] fetchAgentPhone $e');
      return '';
    }
  }

  String? _agentPhoneCache;

  /// Очилган объектларнинг ID'лари — харитада аниқ пин кўрсатиш учун.
  Stream<Set<String>> watchUnlockedIds() {
    final uid = _currentUserId;
    if (uid.isEmpty) return Stream.value(const <String>{});
    return _db
        .collection('users')
        .doc(uid)
        .collection('realty_unlocked')
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.id).toSet());
  }

  /// Пакетда қолган ўринлар сони.
  Stream<int> watchUnlocksLeft() {
    final uid = _currentUserId;
    if (uid.isEmpty) return Stream.value(0);
    return _db.collection('users').doc(uid).snapshots().map(
          (s) => ((s.data() ?? const {})['realtyUnlocksLeft'] as num?)
                  ?.toInt() ??
              0,
        );
  }

  /// Объектни очиш — пакетдан 1 ўрин ейди. Такрор очишда ўрин кетмайди.
  ///
  /// Хатолар: `no_unlocks_left` (пакет тугаган ёки умуман йўқ),
  /// `listing_blocked`, `listing_expired` — бу иккисида ўрин ейилмайди.
  Future<int> unlockListing(String listingId) async {
    final data = await _call('unlockRealtyListing', {'listingId': listingId});
    return (data['unlocksLeft'] as num?)?.toInt() ?? 0;
  }

  /// Ахборот пакети сотиб олиш (5 ёки 10 объект).
  Future<int> purchasePackage(int size) async {
    final data = await _call(
      'purchaseRealtyPackage',
      {'idempotencyKey': _uuid.v4(), 'size': size},
      timeout: _payTimeout,
    );
    return (data['unlocksLeft'] as num?)?.toInt() ?? 0;
  }

  /// Пакет нархлари: ўлчам → нарх.
  Future<Map<int, int>> loadPackagePricing() async {
    final data = await _callOrEmpty('getRealtyPackagePricing');
    return _intMap(data['pricing']);
  }

  /// Бир нечта объектнинг ёпиқ тафсилотини ПАРАЛЛЕЛ ўқийди.
  ///
  /// Аввал харита экрани уларни кетма-кет, битталаб ўқир эди: 10
  /// объектли пакетда бу 10 та кетма-кет бориш-келиш, яъни пинлар
  /// бирин-кетин «сакраб» жойига тушарди. Партия чегараси Firestore'ни
  /// бир вақтда кўп сўров билан кўмиб ташламаслик учун.
  Future<Map<String, RealtyDetail>> fetchDetails(
    Iterable<String> ids, {
    int batchSize = 10,
  }) async {
    final out = <String, RealtyDetail>{};
    final list = ids.toList(growable: false);
    for (var i = 0; i < list.length; i += batchSize) {
      final batch = list.skip(i).take(batchSize);
      final results = await Future.wait(batch.map(fetchDetail));
      var j = 0;
      for (final id in batch) {
        final d = results[j++];
        if (d != null) out[id] = d;
      }
    }
    return out;
  }

  /// Админ модерацияси — статус бўйича навбат.
  ///
  /// [status] `null` бўлса ҳамма ёзув (янгиси юқорида). Фойдаланувчи
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

  /// Кўринадиган эълонлар: муддати тугаганлар ва бошқа битим тури
  /// чиқариб ташланади.
  ///
  /// Тартиб серверда `createdAt` бўйича қўйилади ва филтрлаш уни
  /// бузмайди, шунинг учун бу ерда қайта сортлаш йўқ (аввал бор эди,
  /// лекин `createdAt` бўш ҳужжатда у 0 қайтариб, ҳеч нарсани
  /// ўзгартирмас эди).
  List<RealtyListing> _live(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    RealtyDeal? deal,
  }) {
    return docs
        .map(RealtyListing.fromDoc)
        .where((r) => !r.isExpired)
        .where((r) => deal == null || r.deal == deal)
        .toList();
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
    final data = await _call(
      'submitRealtyListing',
      {
        ..._listingPayload(
          deal: deal,
          title: title,
          text: text,
          lat: lat,
          lng: lng,
          contactMode: contactMode,
          priceText: priceText,
          addressText: addressText,
          rooms: rooms,
          floor: floor,
          totalFloors: totalFloors,
          areaM2: areaM2,
          imageUrls: imageUrls,
        ),
        'idempotencyKey': _uuid.v4(),
        'tier': tier.key,
        if (ownerName.trim().isNotEmpty) 'ownerName': ownerName.trim(),
      },
      timeout: _payTimeout,
    );
    return RealtySubmitResult(
      listingId: (data['listingId'] ?? '') as String,
      status: (data['status'] ?? 'pending') as String,
      freeLeft: (data['freeLeft'] as num?)?.toInt() ?? 0,
    );
  }

  /// Яратиш ва таҳрирлаш учун УМУМИЙ майдонлар.
  ///
  /// Иккала чақирув бир хил майдонларни юборади ва серверда ҳам битта
  /// жойда текширилади (`parseListingInput`). Бўш қиймат `null`
  /// сифатида кетади: таҳрирда бу «майдонни ўчир» дегани, яратишда эса
  /// шунчаки ёзилмайди.
  Map<String, dynamic> _listingPayload({
    required RealtyDeal deal,
    required String title,
    required String text,
    required double lat,
    required double lng,
    required RealtyContactMode contactMode,
    required String priceText,
    required String addressText,
    required int? rooms,
    required int? floor,
    required int? totalFloors,
    required num? areaM2,
    required List<String> imageUrls,
  }) {
    return {
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
    };
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
    final data = await _call(
      'updateRealtyListing',
      {
        ..._listingPayload(
          deal: deal,
          title: title,
          text: text,
          lat: lat,
          lng: lng,
          contactMode: contactMode,
          priceText: priceText,
          addressText: addressText,
          rooms: rooms,
          floor: floor,
          totalFloors: totalFloors,
          areaM2: areaM2,
          imageUrls: imageUrls,
        ),
        'listingId': listingId,
      },
      timeout: _payTimeout,
    );
    return RealtySubmitResult(
      listingId: (data['listingId'] ?? listingId) as String,
      status: (data['status'] ?? 'active') as String,
      freeLeft: 0,
    );
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
    final data = await _call(
      'purchaseRealtyTier',
      {
        'idempotencyKey': _uuid.v4(),
        'listingId': listingId,
        'tier': tier.key,
        'durationDays': durationDays,
      },
      timeout: _payTimeout,
    );
    return RealtyPurchaseResult(
      listingId: (data['listingId'] ?? listingId) as String,
      tier: RealtyTierX.parse(data['tier']),
      durationDays: (data['durationDays'] as num?)?.toInt() ?? durationDays,
      price: (data['price'] as num?)?.toInt() ?? 0,
      tierUntil: DateTime.fromMillisecondsSinceEpoch(
        (data['tierUntil'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// Тариф жадвали: даража → {кун: нарх}. Админ панелдан таҳрирланади.
  ///
  /// Сервер жавоб бермаса бўш жадвал қайтади — чақирувчи «нарх
  /// юкланмади» деб кўрсатсин, ноль нархни эмас.
  Future<Map<RealtyTier, Map<int, int>>> loadPricing() async {
    final data = await _callOrEmpty('getRealtyPricing');
    final pricing = Map<String, dynamic>.from(
      data['pricing'] as Map? ?? const {},
    );
    final out = <RealtyTier, Map<int, int>>{};
    for (final entry in pricing.entries) {
      final days = _intMap(entry.value);
      if (days.isNotEmpty) out[RealtyTierX.parse(entry.key)] = days;
    }
    return out;
  }

  // ─── Видео боғлаш (концепция, 3-бўлим) ───

  /// Объектга видео боғлаш. Бепул AVAGram ёки пуллик реклама эканини
  /// сервер клипнинг ўзидан аниқлайди — клиент айта олмайди.
  Future<void> linkVideo({
    required String listingId,
    required String clipId,
  }) =>
      _call('linkRealtyVideo', {'listingId': listingId, 'clipId': clipId});

  Future<void> unlinkVideo(String listingId) =>
      _call('unlinkRealtyVideo', {'listingId': listingId});

  // ─── Риэлторлик компанияси воситалари (концепция, 5-бўлим) ───

  /// Пакет ҳисоблагичи — банд ўрин, лимит ва муддат.
  Future<RealtyQuota> fetchQuota() async {
    final d = await _callOrEmpty('getRealtyQuota');
    if (d.isEmpty) return RealtyQuota.empty;
    final until = (d['proExpiresAt'] as num?)?.toInt() ?? 0;
    return RealtyQuota(
      used: (d['used'] as num?)?.toInt() ?? 0,
      limit: (d['limit'] as num?)?.toInt() ?? 0,
      isPro: d['isPro'] == true,
      proExpiresAt:
          until > 0 ? DateTime.fromMillisecondsSinceEpoch(until) : null,
    );
  }

  Future<List<RealtyProPlan>> loadProPlans() async {
    final data = await _callOrEmpty('getRealtyProPlans');
    final list = data['plans'] as List? ?? const [];
    return list
        .map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return RealtyProPlan(
            id: (m['id'] ?? '') as String,
            objects: (m['objects'] as num?)?.toInt() ?? 0,
            days: (m['days'] as num?)?.toInt() ?? 0,
            price: (m['price'] as num?)?.toInt() ?? 0,
          );
        })
        .where((p) => p.id.isNotEmpty)
        .toList();
  }

  Future<void> purchaseProPackage(String planId) => _call(
        'purchaseRealtyProPackage',
        {'idempotencyKey': _uuid.v4(), 'planId': planId},
        timeout: _payTimeout,
      );

  /// Сақланган уйлар — янги объектда нуқтани қайта қўйиш ўрнига танлаш.
  Stream<List<RealtySavedPlace>> watchSavedPlaces() {
    final uid = _currentUserId;
    if (uid.isEmpty) return Stream.value(const <RealtySavedPlace>[]);
    return _db
        .collection('users')
        .doc(uid)
        .collection('realty_places')
        .orderBy('label')
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final d = doc.data();
              return RealtySavedPlace(
                id: doc.id,
                label: (d['label'] ?? '') as String,
                lat: (d['lat'] as num?)?.toDouble() ?? 0,
                lng: (d['lng'] as num?)?.toDouble() ?? 0,
              );
            }).toList());
  }

  Future<void> savePlace({
    required String label,
    required double lat,
    required double lng,
  }) async {
    final uid = _currentUserId;
    if (uid.isEmpty) return;
    await _db
        .collection('users')
        .doc(uid)
        .collection('realty_places')
        .add({'label': label.trim(), 'lat': lat, 'lng': lng});
  }

  Future<void> deleteSavedPlace(String placeId) async {
    final uid = _currentUserId;
    if (uid.isEmpty) return;
    await _db
        .collection('users')
        .doc(uid)
        .collection('realty_places')
        .doc(placeId)
        .delete();
  }

  /// Шаблон — компаниянинг стандарт матни ва шартлари (бир марта
  /// киритилади, кейин ҳар объектга автоматик тўлади).
  Future<String> loadTemplateText() async {
    final uid = _currentUserId;
    if (uid.isEmpty) return '';
    try {
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection('realty_prefs')
          .doc('template')
          .get();
      return ((snap.data() ?? const {})['text'] ?? '') as String;
    } catch (e) {
      debugPrint('[RealtyRepository] loadTemplateText $e');
      return '';
    }
  }

  Future<void> saveTemplateText(String text) async {
    final uid = _currentUserId;
    if (uid.isEmpty) return;
    await _db
        .collection('users')
        .doc(uid)
        .collection('realty_prefs')
        .doc('template')
        .set({'text': text.trim()});
  }

  /// Ходимни компания пакетига улаш.
  ///
  /// Хатолар: `pro_required`, `member_not_found`, `member_has_listings`.
  Future<void> addTeamMember(String phone) =>
      _call('addRealtyTeamMember', {'phone': phone});

  Future<void> removeTeamMember(String phone) =>
      _call('removeRealtyTeamMember', {'phone': phone});

  /// Эга ўз объектини ўчиради («сотилди» ёки нотўғри киритилди).
  Future<void> deleteMine(String listingId) =>
      _call('deleteRealtyListing', {'listingId': listingId});
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

/// Пакет ҳисоблагичи (концепция, 5-бўлим: «Пакетда қанча объект ўрни
/// ва муддат қолгани доим кўриниб туради»).
class RealtyQuota {
  const RealtyQuota({
    required this.used,
    required this.limit,
    required this.isPro,
    this.proExpiresAt,
  });

  static const empty = RealtyQuota(used: 0, limit: 0, isPro: false);

  final int used;
  final int limit;
  final bool isPro;
  final DateTime? proExpiresAt;

  int get left => (limit - used).clamp(0, limit);
  bool get isFull => used >= limit;

  int? get proDaysLeft {
    final until = proExpiresAt;
    if (until == null) return null;
    final days = until.difference(DateTime.now()).inDays;
    return days < 0 ? 0 : days;
  }
}

/// Профессионал пакет режаси.
class RealtyProPlan {
  const RealtyProPlan({
    required this.id,
    required this.objects,
    required this.days,
    required this.price,
  });

  final String id;
  final int objects;
  final int days;
  final int price;
}

/// «Сақланган уй» — риэлтор тез-тез ишлайдиган манзил (5-бўлим).
class RealtySavedPlace {
  const RealtySavedPlace({
    required this.id,
    required this.label,
    required this.lat,
    required this.lng,
  });

  final String id;
  final String label;
  final double lat;
  final double lng;
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
