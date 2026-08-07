import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/formatters.dart';
import '../models/job_ad.dart';
import '../models/job_complaint.dart';
import '../services/job_ad_service.dart';

/// `ads` ва `complaints` — Иш топ doskasi.
class JobsRepository {
  JobsRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

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
  Stream<List<JobAd>> watchActiveByType(String type, {int limit = 300}) {
    return _ads
        .where('type', isEqualTo: type)
        .where('status', isEqualTo: 'active')
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(JobAd.fromDoc).toList(growable: false));
  }

  /// Иш / хизмат / эълон feed (актив).
  Stream<List<JobAd>> watchAllActive({int limit = 500}) {
    return _ads
        .where('type', whereIn: ['work', 'service', 'ad'])
        .where('status', isEqualTo: 'active')
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

  /// Admin panel учун: фақат Иш топ doskasi (`work|service|ad`).
  Stream<List<JobAd>> watchAllForAdmin({int limit = 500}) {
    return _ads
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .where(
                (d) => JobAd.isJobsBoardType(
                  (d.data()['type'] ?? '') as String,
                ),
              )
              .map(JobAd.fromDoc)
              .toList(growable: false),
        );
  }

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
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
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
    required String authorName,
    required String authorPhone,
    required String address,
    required bool isUrgent,
    required DateTime expiresAt,
    String title = '',
    String priceText = '',
  }) async {
    if (!JobAd.isJobsBoardType(type)) {
      throw StateError('Номаълум эълон тури');
    }
    final result = await JobAdService.submitAd(
      type: type,
      text: text,
      authorName: authorName,
      title: title,
      priceText: priceText,
      address: address,
      isUrgent: isUrgent,
    );
    return result.status;
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
