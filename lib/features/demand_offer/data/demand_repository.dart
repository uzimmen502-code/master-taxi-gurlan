// ТАЛАБ → ТАКЛИФ ядроси — харидор томони репозиторийси.
//
// АСОСИЙ ҚОИДА (концепция + Т-12):
//   ЁЗИШ  — фақат callable функциялар орқали. Клиент `demands`га
//           ҳеч қачон тўғридан-тўғри ёзмайди (Firestore қоидаси
//           `allow write: if false`).
//   ЎҚИШ  — тўғридан-тўғри Firestore stream. Сабаб: жонли рўйхат
//           керак, callable эса polling талаб қиларди.
//
// РЕГИОН: callable'лар `europe-west1`да (Firestore `eur3` билан бир
// жойда). Мавжуд `AvaFunctions.auth` намунаси билан бир хил.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

import '../domain/demand.dart';
import '../domain/demand_enums.dart';
import '../domain/offer.dart';

/// Ядро callable'лари турган регион.
///
/// `lib/core/firebase_functions_client.dart`даги `AvaFunctions.auth`
/// билан бир хил сабаб: Firestore `eur3`да, функция ҳам Европада
/// бўлиши керак.
const String kDemandCoreRegion = 'europe-west1';

/// Callable натижасидаги хато — фойдаланувчига кўрсатиладиган матн билан.
class DemandException implements Exception {
  const DemandException(this.code, this.message);

  final String code;
  final String message;

  /// Фойдаланувчи қайта уриниши маъноли бўладиган хатоми.
  bool get isRetryable =>
      code == 'unavailable' || code == 'internal' || code == 'deadline-exceeded';

  /// Лимитга урилганми («кунига 10 тадан кўп сўров...»).
  bool get isLimit => code == 'resource-exhausted';

  @override
  String toString() => 'DemandException($code): $message';
}

class DemandRepository {
  DemandRepository({
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

  CollectionReference<Map<String, dynamic>> get _demands =>
      _db.collection('demands');

  /// Т-12 — idempotentlik калити.
  ///
  /// Форма очилганда БИР МАРТА яратилади ва «Юбориш» бир неча марта
  /// босилса ҳам ўзгармайди. Шунда сервер иккинчи чақирувни дублikat
  /// деб таниб, аввалги `demandId`ни қайтаради.
  String newRequestId() => 'req-${_uuid.v4().replaceAll('-', '').substring(0, 20)}';

  // ── ЁЗИШ (фақат callable) ──────────────────────────────────────────

  /// Талаб яратади.
  ///
  /// Юкламада `ownerId`, `mode`, `regionId`, `status` ЙЎҚ — уларни
  /// сервер қўяди ва схема клиентдан келганини рад этади.
  Future<CreateDemandResult> createDemand({
    required DemandModule module,
    required String clientRequestId,
    String? categoryId,
    String source = 'module',
    required Map<String, dynamic> input,
    String? title,
    String? description,
    DemandPoint? location,
    DemandPoint? destination,
    Map<String, dynamic>? timeWindow,
    DemandBudget? budget,
    int? quantity,
    List<String>? images,
    String? recipientName,
    String? recipientPhone,
    Map<String, dynamic>? attributes,
    String? payerSide,
    DateTime? termsAcceptedAt,
  }) async {
    final payload = <String, dynamic>{
      'module': module.wire,
      'clientRequestId': clientRequestId,
      'source': source,
      'input': input,
      if (categoryId != null) 'categoryId': categoryId,
      if (title != null && title.isNotEmpty) 'title': title,
      if (description != null && description.isNotEmpty)
        'description': description,
      if (location != null) 'location': location.toInput(),
      if (destination != null) 'destination': destination.toInput(),
      if (timeWindow != null) 'timeWindow': timeWindow,
      if (budget != null) 'budget': budget.toInput(),
      if (quantity != null) 'quantity': quantity,
      if (images != null && images.isNotEmpty) 'media': {'images': images},
      if (recipientPhone != null && recipientPhone.isNotEmpty)
        'contact': {
          'recipientName': recipientName ?? '',
          'recipientPhone': recipientPhone,
        },
      if (attributes != null && attributes.isNotEmpty) 'attributes': attributes,
      if (payerSide != null) 'payerSide': payerSide,
      if (termsAcceptedAt != null)
        'termsAcceptedAt': termsAcceptedAt.toUtc().toIso8601String(),
    };

    final data = await _call('createDemand', payload);
    return CreateDemandResult(
      demandId: (data['demandId'] ?? '').toString(),
      duplicate: data['duplicate'] == true,
      matchedBucket: MatchedBucket.parse(data['matchedBucket']?.toString()),
      matchingState:
          DemandMatchingState.tryParse(data['matchingState']?.toString()) ??
              DemandMatchingState.pending,
    );
  }

  /// Таклифни қабул қилиш. Биринчи қабул ғолиб (сервер транзакцияси).
  Future<void> acceptOffer({
    required String demandId,
    required String providerId,
  }) async {
    await _call('acceptOffer', {
      'demandId': demandId,
      'providerId': providerId,
    });
  }

  /// Мижоз талабни бекор қилади. Сабаб СЎРАЛМАЙДИ (концепция қоидаси).
  Future<void> cancelDemand(String demandId) async {
    await _call('cancelDemand', {'demandId': demandId});
  }

  /// Баҳо — фақат бажарилган иш бўйича.
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

  // ── ЎҚИШ (жонли Firestore) ─────────────────────────────────────────

  /// «Менинг сўровларим» — жонли рўйхат.
  ///
  /// `expiresAt` фильтри ИЛОВАДА ҳам қўлланади (Т-5): сервер sweeper'и
  /// кечикса ҳам эскирган талаб рўйхатда кўринмайди.
  Stream<List<Demand>> myDemands(String ownerId, {int limit = 50}) {
    return _demands
        .where('ownerId', isEqualTo: ownerId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final now = DateTime.now();
      return snap.docs
          .map((d) => Demand.fromMap(d.id, d.data()))
          .where((d) => d.isVisibleAt(now))
          .toList();
    });
  }

  /// Модул ичидаги фильтрланган кўриниш.
  ///
  /// Концепция: «Ҳар бир модул ичида ўша модулга тегишли сўровлар ҳам
  /// кўринади. Бу ўша маълумотнинг фильтрланган кўриниши.»
  Stream<List<Demand>> myDemandsForModule(
    String ownerId,
    DemandModule module, {
    int limit = 50,
  }) {
    return myDemands(ownerId, limit: limit)
        .map((list) => list.where((d) => d.module == module).toList());
  }

  /// Битта талаб — жонли.
  Stream<Demand?> watchDemand(String demandId) {
    return _demands.doc(demandId).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      return Demand.fromMap(snap.id, data);
    });
  }

  /// Талабга келган таклифлар — жонли.
  ///
  /// МАХФИЙЛИК: Firestore қоидаси таклифни фақат унинг эгаси ва талаб
  /// эгасига беради. Таклифчилар бир-бирининг нархини кўрмайди.
  Stream<OfferList> watchOffers(String demandId) {
    return _demands
        .doc(demandId)
        .collection('offers')
        .snapshots()
        .map((snap) => OfferList(
              snap.docs.map((d) => Offer.fromMap(d.id, d.data())).toList(),
            ));
  }

  /// Актив сўровлар сони — «Фаолият» таби badge'и учун.
  Stream<int> activeDemandCount(String ownerId) {
    return _demands
        .where('ownerId', isEqualTo: ownerId)
        .where('status', isEqualTo: DemandStatus.active.wire)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  // ── Ички ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await _fn.httpsCallable(name).call<Object?>(payload);
      final data = res.data;
      if (data is Map) {
        return data.map((k, v) => MapEntry(k.toString(), v));
      }
      return <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      // Сервер юборган матн фойдаланувчи учун ёзилган (ўзбекча),
      // шунинг учун тўғридан-тўғри кўрсатилади.
      throw DemandException(e.code, e.message ?? 'Xatolik yuz berdi');
    } catch (e) {
      throw DemandException('unknown', e.toString());
    }
  }
}

/// `createDemand` натижаси.
class CreateDemandResult {
  const CreateDemandResult({
    required this.demandId,
    required this.duplicate,
    required this.matchedBucket,
    required this.matchingState,
  });

  final String demandId;

  /// Икки марта тап — янги талаб яратилмади (Т-12).
  final bool duplicate;

  /// Т-8: аниқ рақам эмас, панжара («30+»).
  final MatchedBucket matchedBucket;

  final DemandMatchingState matchingState;

  /// Мос таклифчи топилмадими.
  ///
  /// Шунда фойдаланувчига «Ҳозирча мос таклифчи йўқ. Пайдо бўлса, хабар
  /// берамиз» кўрсатилади — бўш экран ЭМАС (концепция талаби).
  bool get noProviders => matchingState == DemandMatchingState.noProviders;
}
