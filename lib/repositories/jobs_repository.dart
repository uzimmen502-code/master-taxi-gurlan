import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/geo/geo_context.dart';
import '../core/geo/geo_query.dart';
import '../core/utils/formatters.dart';
import '../models/job_ad.dart';
import '../models/job_complaint.dart';
import '../services/job_ad_service.dart';

/// `ads` ва `complaints` — Иш топ doskasi.
class JobsRepository {
  JobsRepository({FirebaseFirestore? db}) : _dbOverride = db;

  final FirebaseFirestore? _dbOverride;

  /// Кечиктирилган: репозиторийни Firebase'сиз яратиш мумкин (виджет
  /// тестларида контроллер ишлатилганда); биринчи сўровда олинади.
  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _ads => _db.collection('ads');
  CollectionReference<Map<String, dynamic>> get _complaints =>
      _db.collection('complaints');

  static String _normPhone(String raw) => canonicalPhoneId(raw);

  static bool _urgentForType(String type, bool isUrgent) {
    if (!isUrgent) return false;
    return type == 'work' || type == 'ad';
  }

  void _assertOwner(JobAd ad, String callerPhone) {
    final caller = _normPhone(callerPhone);
    if (phoneDigits(caller).length < 9) {
      throw StateError('Телефон киритилмаган');
    }
    if (!phonesMatch(ad.authorPhone, caller)) {
      throw StateError('Бу эълон сизга тегишли эмас');
    }
  }

  /// Берилган тип ва active статусга эга охирги эълонлар.
  ///
  /// `orderBy` шарт: аввал йўқ эди — эълонлар [limit]дан кўпайганда
  /// тасодифий қисм келарди (geo аудит, 0-босқич). Индекс:
  /// `ads (type, status, createdAt↓)`.
  Stream<List<JobAd>> watchActiveByType(String type, {int limit = 300}) {
    return _ads
        .where('type', isEqualTo: type)
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(JobAd.fromDoc).toList(growable: false));
  }

  /// Ҳудуд даражаси бўйича фаол эълонлар (D-GEO-1, 2-такомиллаштириш).
  /// [types] — `ad` / `service` / `work`. Сервер филтри; ҳудудсиз эски
  /// эълонлар туман/вилоятда ҳам. Муддати ўтганлар чиқарилади.
  /// Индекс: `ads (type, status, districtId, createdAt↓)`; тур × туман
  /// `in` кўпайтмаси ≤ 30 — туманлар 10 тадан бўлак.
  Stream<List<JobAd>> watchScoped(
    GeoScope scope, {
    List<String> types = const ['work', 'service', 'ad'],
    int limit = 500,
  }) {
    Query<Map<String, dynamic>> byType(Query<Map<String, dynamic>> q) =>
        types.length == 1
            ? q.where('type', isEqualTo: types.first)
            : q.where('type', whereIn: types);
    List<JobAd> map(QuerySnapshot<Map<String, dynamic>> s) =>
        s.docs.map(JobAd.fromDoc).where((a) => !a.isExpired).toList();
    return geoScopedStream<JobAd>(
      scope: scope,
      nation: () => byType(_ads)
          .where('status', isEqualTo: 'active')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map(map),
      byDistricts: (ids) => byType(_ads)
          .where('status', isEqualTo: 'active')
          .where('districtId', whereIn: ids)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map(map),
      legacy: () => byType(_ads)
          .where('status', isEqualTo: 'active')
          .orderBy('createdAt', descending: true)
          .limit(60)
          .snapshots()
          .map((s) => map(s).where((a) => a.districtId.trim().isEmpty).toList()),
      idOf: (a) => a.id,
      compare: (a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.createdAt?.millisecondsSinceEpoch ?? 0),
      limit: limit,
      chunkSize: types.length > 1 ? 10 : 30,
    );
  }


  /// Иш / хизмат / эълон feed (актив) — энг янгилари (`orderBy` — юқорига
  /// қаранг).
  Stream<List<JobAd>> watchAllActive({int limit = 500}) {
    return _ads
        .where('type', whereIn: ['work', 'service', 'ad'])
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(JobAd.fromDoc).toList(growable: false));
  }

  /// Муаллифнинг барча эълонлари — 9 / 998 алиаслар.
  Stream<List<JobAd>> watchAdsByAuthor(String authorPhone, {int limit = 50}) {
    final aliases = phoneAliases(authorPhone)
        .map(phoneDigits)
        .where((p) => p.length >= 9)
        .toSet()
        .take(10)
        .toList(growable: false);
    if (aliases.isEmpty) return Stream.value(const []);

    return _ads
        .where('authorPhone', whereIn: aliases)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map(JobAd.fromDoc)
          .where((a) => JobAd.isJobsBoardType(a.type))
          .toList(growable: false);
      list.sort((a, b) {
        final at = a.createdAt;
        final bt = b.createdAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
      return list;
    });
  }

  /// Admin panel рўйхати: фақат Иш топ doskasi (`work|service|ad`), энг
  /// янгиси биринчи. Саҳифалар (500 та + «Яна юклаш») — экранда,
  /// `AdminPagedList` орқали.
  ///
  /// Тур филтри СЕРВЕРДА (2026-10-08): аввал бутун `ads` коллекциясидан
  /// охирги 500 таси олиниб, клиентда филтрланарди — бозор эълонлари
  /// ўринларни эгаллаб, иш эълонлари рўйхати ва жами сонлари қисқариб
  /// қоларди. Индекс: ads (type ASC, createdAt DESC).
  Query<Map<String, dynamic>> adminListQuery() => _ads
      .where('type', whereIn: JobAd.jobsBoardTypes)
      .orderBy('createdAt', descending: true);

  /// Шикоятлар (янги юқорида).
  Stream<List<JobComplaint>> watchComplaints({int limit = 200}) {
    return _complaints
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map(JobComplaint.fromDoc).toList(growable: false),
        );
  }

  Future<JobAd?> getAdById(String adId) async {
    if (adId.isEmpty) return null;
    final snap = await _ads.doc(adId).get();
    if (!snap.exists) return null;
    return JobAd.fromDoc(snap);
  }

  /// Бугунги ИШ ЭЪЛОН сони (UI hint; сервер ҳам текширади).
  /// `cheap_product` ва бошқа турлар ҳисобга олинмайди.
  Future<int> dailyCountByAuthor(String authorPhone) async {
    final aliases = phoneAliases(authorPhone)
        .map(phoneDigits)
        .where((p) => p.length >= 9)
        .toSet()
        .take(10)
        .toList(growable: false);
    if (aliases.isEmpty) return 0;
    // Сервер лимитни ТОШКЕНТ куни бўйича ҳисоблайди — клиент ҳам шундай
    // (қурилма вақт зонасига боғлиқ эмас).
    final startOfDay = tashkentDayStartUtc(DateTime.now());
    try {
      var total = 0;
      for (final phone in aliases) {
        final snap = await _ads
            .where('authorPhone', isEqualTo: phone)
            .where('createdAt',
                isGreaterThan: Timestamp.fromDate(startOfDay))
            .get();
        for (final doc in snap.docs) {
          final type = (doc.data()['type'] ?? '') as String;
          if (JobAd.isJobsBoardType(type)) total += 1;
        }
      }
      return total;
    } catch (e) {
      throw StateError('Индекс ёки сўров хатоси: $e');
    }
  }

  /// Янги эълон — CF `submitJobAd` (auth + canonical phone + лимит).
  /// Қайтиш: сервер статуси (`pending` | `active`).
  Future<String> addAd({
    required String type,
    required String text,
    required bool isUrgent,
    String title = '',
    String priceText = '',
    String requestId = '',
  }) async =>
      (await addAdWithId(
        type: type,
        text: text,
        isUrgent: isUrgent,
        title: title,
        priceText: priceText,
        requestId: requestId,
      ))
          .status;

  /// [addAd] билан бир хил, лекин яратилган эълон `id`си ҳам қайтади — унга
  /// ихтиёрий видео боғлаш учун ([TvClipLink]).
  ///
  /// Эга номи, телефон, ҳудуд ва муддат СЕРВЕРДА белгиланади (аудит B6).
  Future<({String adId, String status})> addAdWithId({
    required String type,
    required String text,
    required bool isUrgent,
    String title = '',
    String priceText = '',
    String requestId = '',
  }) async {
    if (!JobAd.isJobsBoardType(type)) {
      throw StateError('Номаълум эълон тури');
    }
    return JobAdService.submitAd(
      type: type,
      text: text,
      title: title,
      priceText: priceText,
      isUrgent: isUrgent,
      requestId: requestId,
    );
  }

  /// Муаллиф ўз эълони (authorPhone текшируви).
  Future<void> updateAdByOwner({
    required String adId,
    required String callerPhone,
    required String text,
    required bool isUrgent,
    required String type,
    String? title,
    String? priceText,
  }) async {
    final snap = await _ads.doc(adId).get();
    if (!snap.exists) throw StateError('Эълон топилмади');
    final ad = JobAd.fromDoc(snap);
    _assertOwner(ad, callerPhone);
    final updates = <String, dynamic>{
      'text': text,
      'isUrgent': _urgentForType(type, isUrgent),
      'type': type,
      'editedAt': FieldValue.serverTimestamp(),
      'title': title ?? ad.title,
      'priceText': priceText ?? ad.priceText,
    };
    await _ads.doc(adId).update(updates);
  }

  /// Admin moderation: статус ва контент.
  Future<void> updateAd({
    required String adId,
    required String text,
    required bool isUrgent,
    required String type,
    String? status,
    String? title,
    String? priceText,
    String? address,
    DateTime? expiresAt,
    String? adminNote,
    String? moderatedBy,
  }) async {
    final updates = <String, dynamic>{
      'text': text,
      'isUrgent': _urgentForType(type, isUrgent),
      'type': type,
      'editedAt': FieldValue.serverTimestamp(),
      'moderatedAt': FieldValue.serverTimestamp(),
    };
    if (status != null) updates['status'] = status;
    if (title != null) updates['title'] = title;
    if (priceText != null) updates['priceText'] = priceText;
    if (address != null) updates['address'] = address;
    if (expiresAt != null) {
      updates['expiresAt'] = Timestamp.fromDate(expiresAt);
    }
    if (adminNote != null) updates['adminNote'] = adminNote;
    if (moderatedBy != null && moderatedBy.isNotEmpty) {
      updates['moderatedBy'] = moderatedBy;
    }
    await _ads.doc(adId).update(updates);
  }

  Future<void> updateAdStatus({
    required String adId,
    required String status,
    String? moderatedBy,
  }) async {
    final updates = <String, dynamic>{
      'status': status,
      'moderatedAt': FieldValue.serverTimestamp(),
      'editedAt': FieldValue.serverTimestamp(),
    };
    if (moderatedBy != null && moderatedBy.isNotEmpty) {
      updates['moderatedBy'] = moderatedBy;
    }
    await _ads.doc(adId).update(updates);
  }

  /// Муаллиф ўз эълони (ўчириш).
  Future<void> deleteAdByOwner({
    required String adId,
    required String callerPhone,
  }) async {
    final snap = await _ads.doc(adId).get();
    if (!snap.exists) return;
    _assertOwner(JobAd.fromDoc(snap), callerPhone);
    await _ads.doc(adId).delete();
  }

  /// Admin: эълонни ўчириш (faqat jobs board).
  Future<void> deleteAdAdmin(String adId) async {
    if (adId.isEmpty) return;
    final snap = await _ads.doc(adId).get();
    if (!snap.exists) return;
    final type = (snap.data()?['type'] ?? '') as String;
    if (!JobAd.isJobsBoardType(type)) {
      throw StateError('Bu e\'lon Ish top doskasi emas');
    }
    await _ads.doc(adId).delete();
  }

  /// Шikoyatni hal qiling deb belgilash.
  Future<void> resolveComplaint({
    required String complaintId,
    required String resolvedBy,
  }) async {
    if (complaintId.isEmpty || resolvedBy.isEmpty) return;
    await _complaints.doc(complaintId).update({
      'resolved': true,
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedBy': resolvedBy,
    });
  }

  /// Эълонга шикоят — CF `submitJobComplaint`.
  Future<void> addComplaint({
    required String adId,
    required String reason,
    String reporterPhone = '',
  }) async {
    await JobAdService.submitComplaint(adId: adId, reason: reason);
  }
}
