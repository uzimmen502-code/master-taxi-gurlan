import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/geo/geo_context.dart';
import '../../../core/geo/geo_query.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/utils/formatters.dart';
import '../models/yuk_local_driver.dart';
import '../yuk_accept_radius.dart';
import '../yuk_local_schedule.dart';
import '../../yuk_shared/yuk_vehicle_types.dart';

/// Firestore `yuk_local_drivers/{autoId}` — туман ичида эълонлар.
///
/// Эгалик `ownerId` (каноник телефон). Бир фойдаланувчи бир нечта эълон
/// қўшиши мумкин. Кўриниш: жойлашув + иш вақти + expiresAt (онлайн йўқ).
class YukLocalDriversRepository {
  YukLocalDriversRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _functions = functions;

  final FirebaseFirestore _db;
  final FirebaseFunctions? _functions;
  FirebaseFunctions get _fns => _functions ?? FirebaseFunctions.instance;

  static const int watchLimit = 200;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('yuk_local_drivers');

  /// Каталог (қидирув) — онлайн фильтрсиз; клиентда иш вақти/TTL/GPS.
  ///
  /// Ҳудуд филтри СЕРВЕРДА ([geoScopedStream], 3а-босқич): туман →
  /// `districtId ==`, вилоят → `districtId in` вилоят туманлари. Лимит ҳар
  /// доим шу ҳудуд эълонларига тегишли — бошқа ҳудуд лимитни «еб қўймайди».
  /// Бир майдонли `in` + `limit` — композит индекс керак эмас.
  ///
  /// Ҳудудсиз эълонлар (туман аниқланмаган): сервер триггери
  /// (`onYukLocalDriverWrite`) йўқ `districtId`ни `''` қилиб ёзади — шу
  /// сабабли улар аниқ `== ''` сўрови билан келади. Аввал бу оқим бутун
  /// коллекциядан тартибсиз 200 тагача ҳужжат ўқирди (аудит P-4).
  Stream<List<YukLocalDriver>> watchScoped(
    GeoScope scope, {
    int limit = watchLimit,
  }) {
    int ms(YukLocalDriver d) =>
        (d.updatedAt ?? d.createdAt)?.millisecondsSinceEpoch ?? 0;
    return geoScopedStream<YukLocalDriver>(
      scope: scope,
      // Бир майдонли orderBy + limit — композит индекс керак эмас.
      nation: () => _col
          .orderBy('updatedAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((snap) => snap.docs.map(_fromDoc).toList()),
      byDistricts: (ids) => _col
          .where('districtId', whereIn: ids)
          .limit(limit)
          .snapshots()
          .map((snap) => snap.docs.map(_fromDoc).toList()),
      legacy: () => _col
          .where('districtId', isEqualTo: '')
          .limit(limit)
          .snapshots()
          .map((snap) => snap.docs.map(_fromDoc).toList()),
      idOf: (d) => d.id,
      compare: (a, b) => ms(b).compareTo(ms(a)),
      limit: limit,
    );
  }

  /// Ўз эълонлари — `createdAt` бўйича (янги тепада).
  Stream<List<YukLocalDriver>> watchMine(String ownerId) {
    final id = canonicalPhoneId(ownerId);
    if (id.isEmpty) {
      return Stream.value(const <YukLocalDriver>[]);
    }
    return _col.where('ownerId', isEqualTo: id).snapshots().map((snap) {
      final docs = snap.docs.toList()
        ..sort((a, b) {
          final at = a.data()['createdAt'];
          final bt = b.data()['createdAt'];
          if (at is Timestamp && bt is Timestamp) return bt.compareTo(at);
          if (at is Timestamp) return -1;
          if (bt is Timestamp) return 1;
          return a.id.compareTo(b.id);
        });
      return docs.map(_fromDoc).toList();
    });
  }

  DocumentReference<Map<String, dynamic>> _ownerMeta(String ownerId) =>
      _db.collection('yuk_local_owner_meta').doc(ownerId);

  /// Биринчи эълон эдими (ўчирилганлар ҳам ҳисобга — meta).
  Future<bool> _ownerHadListingBefore(String ownerId) async {
    final meta = await _ownerMeta(ownerId).get();
    if (meta.data()?['everPublished'] == true) return true;
    final snap = await _col.where('ownerId', isEqualTo: ownerId).limit(1).get();
    return snap.docs.isNotEmpty;
  }

  /// Янги эълон учун ID — форма очилганда БИР марта олинади ва ҳар уринишда
  /// [publishListing] га `docId` сифатида берилади: ёзув аслида тушиб, жавоб
  /// хато қайтса ҳам, қайта юбориш ўша ҳужжатни янгилайди — иккинчи эълон
  /// пайдо бўлмайди (C-2, 21-банд). Тармоқ сўрови йўқ (ID клиентда ясалади).
  String newListingId() => _col.doc().id;

  /// Яратиш/таҳрир — GPS + иш вақти мажбурий. Онлайн/heartbeat йўқ.
  ///
  /// [docId] бўш → янги эълон. Қайтаради: ҳужжат ID.
  Future<String> publishListing({
    String? docId,
    required String ownerId,
    required String ownerName,
    required String phone,
    required String vehicleType,
    required String plateNumber,
    required double capacityKg,
    required double bodyLengthM,
    required double bodyWidthM,
    required double bodyHeightM,
    required int acceptRadiusKm,
    required YukLocalLoadStatus loadStatus,
    required double lat,
    required double lng,
    required int workStartMinutes,
    required int workEndMinutes,
    String locationLabel = '',
    String districtId = '',
    String regionId = '',
  }) async {
    final id = canonicalPhoneId(ownerId);
    if (id.isEmpty) {
      throw StateError('ownerId required');
    }
    final callPhone = phone.trim().isNotEmpty
        ? phone.trim()
        : (id.length >= 12 ? '+$id' : id);
    final trimmedDocId = (docId ?? '').trim();
    final ref = trimmedDocId.isEmpty ? _col.doc() : _col.doc(trimmedDocId);
    final existing = await ref.get();

    final start = YukLocalSchedule.clampMinutes(workStartMinutes);
    final end = YukLocalSchedule.clampMinutes(workEndMinutes);

    final payload = <String, dynamic>{
      'ownerId': id,
      'ownerName': ownerName.trim(),
      'phone': callPhone,
      'vehicleType': normalizeYukVehicleType(vehicleType),
      'plateNumber': plateNumber.trim().toUpperCase(),
      'capacityKg': capacityKg,
      'capacityTons': FieldValue.delete(),
      'bodyLengthM': bodyLengthM,
      'bodyWidthM': bodyWidthM,
      'bodyHeightM': bodyHeightM,
      'acceptRadiusKm': YukAcceptRadius.normalize(acceptRadiusKm),
      'loadStatus': loadStatus == YukLocalLoadStatus.offline
          ? YukLocalLoadStatus.empty.wire
          : loadStatus.wire,
      'lat': lat,
      'lng': lng,
      if (locationLabel.trim().isNotEmpty) 'locationLabel': locationLabel.trim(),
      'workStartMinutes': start,
      'workEndMinutes': end,
      'updatedAt': FieldValue.serverTimestamp(),
      // Ҳудуд муҳри — рўйхатни туман бўйича филтрлаш учун. `reportStamp`
      // фақат бўш бўлмаган қийматларни беради, шунинг учун ҳудуд ҳали
      // танланмаган бўлса эски хатти-ҳаракат сақланади.
      ...ServiceConfigHolder.reportStamp(),
      // Эга қарори 2026-10-31: эълон тумани — машина ТУРГАН жой (GPS).
      // Аниқланса профил муҳри устидан ёзилади.
      if (districtId.trim().isNotEmpty) ...{
        'districtId': districtId.trim(),
        if (regionId.trim().isNotEmpty) 'regionId': regionId.trim(),
      },
    };

    if (!existing.exists) {
      final hadBefore = await _ownerHadListingBefore(id);
      final ttl = hadBefore
          ? YukLocalSchedule.nextListingTtl
          : YukLocalSchedule.firstListingTtl;
      payload.addAll({
        'rating': 0,
        'completedLoads': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(ttl)),
      });
    } else {
      // Эски онлайн модель қолдиқларини тозалаш.
      payload['online'] = FieldValue.delete();
      payload['lastOnlineAt'] = FieldValue.delete();
    }

    await ref.set(payload, SetOptions(merge: true));
    await _ownerMeta(id).set({
      'everPublished': true,
      'ownerId': id,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return ref.id;
  }

  Future<void> deleteMine(String docId) async {
    if (docId.trim().isEmpty) return;
    await _col.doc(docId).delete();
  }

  /// «Узайтириш» — муддатни сервер +30 кунга чўзади (эга қарори 2026-10-31).
  /// Муддат клиентда ёзилмайди (rules `expiresAt`ни қулфлаган); қайта
  /// чақирилса сервер иккинчи марта чўзмайди. Қайтаради: янги муддат.
  Future<DateTime?> renewListing(String listingId) async {
    final id = listingId.trim();
    if (id.isEmpty) return null;
    final res = await _fns
        .httpsCallable('renewYukLocalListing')
        .call<Object?>({'listingId': id});
    final data = res.data;
    if (data is Map) {
      final ms = data['expiresAtMs'];
      if (ms is num) return DateTime.fromMillisecondsSinceEpoch(ms.toInt());
    }
    return null;
  }

  Future<void> updateAcceptRadius({
    required String docId,
    required int acceptRadiusKm,
  }) async {
    if (docId.trim().isEmpty) return;
    await _col.doc(docId).set({
      'acceptRadiusKm': YukAcceptRadius.normalize(acceptRadiusKm),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  YukLocalDriver _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return YukLocalDriver.fromFirestore(doc.id, doc.data() ?? {});
  }
}
