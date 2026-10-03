// ТАЛАБ → ТАКЛИФ ядроси — ТАКЛИФЧИ томони репозиторийси.
//
// МАНБА: `demand_matches` коллекцияси. Таклифчи `demands` ҳужжатини
// ҲЕЧ ҚАЧОН ўқимайди — Firestore қоидаси рад этади.
//
// ДИҚҚАТ — сўров шакли ЎЗГАРТИРИЛМАЙДИ:
//   .where('providerId', isEqualTo: <ўз ID>)
// Firestore қоидаси `resource.data.providerId`ни текширади, шунинг учун
// фильтрсиз сўров `permission-denied` билан рад этилади. Бу хато эмас,
// ҲИМОЯ: таклифчи бошқаларнинг match'ларини сўраб кўра олмайди.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

import '../domain/demand_enums.dart';
import '../domain/demand_match.dart';
import 'demand_repository.dart' show DemandException, kDemandCoreRegion;

class MatchRepository {
  MatchRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    Uuid? uuid,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _fn = functions ??
            FirebaseFunctions.instanceFor(region: kDemandCoreRegion),
        _uuid = uuid ?? const Uuid();

  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;
  final Uuid _uuid;

  CollectionReference<Map<String, dynamic>> get _matches =>
      _db.collection('demand_matches');

  String newRequestId() =>
      'req-${_uuid.v4().replaceAll('-', '').substring(0, 20)}';

  // ── ЎҚИШ ───────────────────────────────────────────────────────────

  /// «Менга келган сўровлар» — жонли рўйхат, score бўйича.
  ///
  /// Индекс: `demand_matches(providerId ASC, score DESC)`.
  Stream<List<DemandMatch>> myMatches(String providerId, {int limit = 50}) {
    return _matches
        .where('providerId', isEqualTo: providerId)
        .orderBy('score', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final now = DateTime.now();
      return snap.docs
          .map((d) => DemandMatch.fromMap(d.id, d.data()))
          .where((m) => m.isVisibleAt(now))
          .toList();
    });
  }

  /// Модул бўйича ажратилган кўриниш.
  ///
  /// Курьер ва ҳайдовчилар учун бу рўйхат иш режими экранида, «Онлайн»
  /// тугмаси ёнида туради.
  Stream<List<DemandMatch>> myMatchesForModule(
    String providerId,
    DemandModule module, {
    int limit = 50,
  }) {
    return _matches
        .where('providerId', isEqualTo: providerId)
        .where('module', isEqualTo: module.wire)
        .orderBy('score', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final now = DateTime.now();
      return snap.docs
          .map((d) => DemandMatch.fromMap(d.id, d.data()))
          .where((m) => m.isVisibleAt(now))
          .toList();
    });
  }

  /// Янги (кўрилмаган) сўровлар сони — «Фаолият» badge'и.
  Stream<int> newMatchCount(String providerId) {
    return _matches
        .where('providerId', isEqualTo: providerId)
        .where('status', isEqualTo: MatchStatus.isNew.wire)
        .snapshots()
        .map((snap) {
      final now = DateTime.now();
      return snap.docs
          .map((d) => DemandMatch.fromMap(d.id, d.data()))
          .where((m) => m.isVisibleAt(now))
          .length;
    });
  }

  /// Битта match — жонли (тафсилот экрани учун).
  Stream<DemandMatch?> watchMatch(String demandId, String providerId) {
    return _matches.doc('${demandId}_$providerId').snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      return DemandMatch.fromMap(snap.id, data);
    });
  }

  // ── ЁЗИШ ───────────────────────────────────────────────────────────

  /// «Кўрдим» белгиси — ЯГОНА рухсат этилган клиент ёзуви.
  ///
  /// Firestore қоидаси фақат `status` ва `seenAt` майдонларини
  /// ўзгартиришга рухсат беради; `score`, `projection`, `providerId`
  /// каби майдонларга тегиб бўлмайди.
  ///
  /// Нега callable эмас: бу маълумот муҳим эмас (аналитика ва такрор
  /// push'ни камайтириш учун), ҳар рўйхат очилганда callable чақириш эса
  /// бекорга қиммат.
  Future<void> markSeen(String demandId, String providerId) async {
    try {
      await _matches.doc('${demandId}_$providerId').update({
        'status': MatchStatus.seen.wire,
        'seenAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Кўрилган белгиси ёзилмаса ҳеч нарса бузилмайди — эътиборсиз.
    }
  }

  /// Таклифчи сўровни ўтказиб юборди.
  Future<void> markSkipped(String demandId, String providerId) async {
    try {
      await _matches.doc('${demandId}_$providerId').update({
        'status': MatchStatus.skipped.wire,
        'seenAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Эътиборсиз.
    }
  }

  /// Таклиф беради.
  Future<SubmitOfferResult> submitOffer({
    required String demandId,
    required String clientRequestId,
    num? price,
    String priceType = 'fixed',
    int? quantity,
    String message = '',
    int? etaMinutes,
    bool delivery = false,
    List<String> media = const [],
  }) async {
    final data = await _call('submitOffer', {
      'demandId': demandId,
      'clientRequestId': clientRequestId,
      if (price != null) 'price': price,
      'priceType': priceType,
      if (quantity != null) 'quantity': quantity,
      if (message.isNotEmpty) 'message': message,
      if (etaMinutes != null) 'etaMinutes': etaMinutes,
      'delivery': delivery,
      if (media.isNotEmpty) 'media': media,
    });
    return SubmitOfferResult(
      offerId: (data['offerId'] ?? '').toString(),
      duplicate: data['duplicate'] == true,
      revision: (data['revision'] as num?)?.toInt() ?? 0,
    );
  }

  /// Таклифни қайтариб олади.
  Future<void> withdrawOffer(String demandId) async {
    await _call('withdrawOffer', {'demandId': demandId});
  }

  /// Ижрочи буюртмани бекор қилади — талаб ҚАЙТА ОЧИЛАДИ.
  Future<void> cancelAssignment(String demandId) async {
    await _call('cancelAssignment', {'demandId': demandId});
  }

  /// Икки томон ҳам бир-бирини баҳолайди.
  Future<void> submitRating({
    required String demandId,
    required int stars,
    String comment = '',
  }) async {
    await _call('submitRating', {
      'demandId': demandId,
      'stars': stars,
      if (comment.isNotEmpty) 'comment': comment,
    });
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await _fn.httpsCallable(name).call<Object?>(payload);
      final data = res.data;
      if (data is Map) return data.map((k, v) => MapEntry(k.toString(), v));
      return <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      throw DemandException(e.code, e.message ?? 'Xatolik yuz berdi');
    } catch (e) {
      throw DemandException('unknown', e.toString());
    }
  }
}

class SubmitOfferResult {
  const SubmitOfferResult({
    required this.offerId,
    required this.duplicate,
    required this.revision,
  });

  final String offerId;
  final bool duplicate;

  /// Нечанчи таҳрир. Чегара `module_config.maxOfferRevisions` (3).
  final int revision;
}
