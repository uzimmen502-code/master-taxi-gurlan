import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/formatters.dart';
import '../models/job_ad.dart';
import '../models/job_complaint.dart';

/// `ads` ва `complaints` collection'лар билан ишлайди.
class JobsRepository {
  JobsRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _ads => _db.collection('ads');
  CollectionReference<Map<String, dynamic>> get _complaints =>
      _db.collection('complaints');

  static String _normPhone(String raw) => phoneDigits(raw.trim());

  static bool _urgentForType(String type, bool isUrgent) {
    if (!isUrgent) return false;
    return type == 'work' || type == 'ad';
  }

  void _assertOwner(JobAd ad, String callerPhone) {
    final caller = _normPhone(callerPhone);
    if (caller.isEmpty) {
      throw StateError('Телефон киритилмаган');
    }
    if (!phonesMatch(ad.authorPhone, caller)) {
      throw StateError('Бу эълон сизга тегишли эмас');
    }
  }

  /// Берилган тип ва active статусга эга охирги 50 та эълонни кузатиш.
  Stream<List<JobAd>> watchActiveByType(String type, {int limit = 50}) {
    return _ads
        .where('type', isEqualTo: type)
        .where('status', isEqualTo: 'active')
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(JobAd.fromDoc).toList(growable: false));
  }

  /// 3 та тип бирваракай (work + service + ad). Mini-OLX ягона feed учун.
  Stream<List<JobAd>> watchAllActive({int limit = 100}) {
    return _ads
        .where('type', whereIn: ['work', 'service', 'ad', 'sell'])
        .where('status', isEqualTo: 'active')
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(JobAd.fromDoc).toList(growable: false));
  }

  /// Муаллифнинг барча эълонлари (pending, active, …).
  Stream<List<JobAd>> watchAdsByAuthor(String authorPhone, {int limit = 30}) {
    final phone = _normPhone(authorPhone);
    if (phone.isEmpty) return Stream.value(const []);
    return _ads
        .where('authorPhone', isEqualTo: phone)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(JobAd.fromDoc).toList(growable: false);
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

  /// Admin panel учун: барча эълонлар.
  Stream<List<JobAd>> watchAllForAdmin({int limit = 300}) {
    return _ads
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(JobAd.fromDoc).toList(growable: false));
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

  /// Бугун ушбу муаллиф томонидан қўшилган эълонлар сони (кунлик лимит).
  Future<int> dailyCountByAuthor(String authorPhone) async {
    final phone = _normPhone(authorPhone);
    if (phone.isEmpty) return 0;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    try {
      final snap = await _ads
          .where('authorPhone', isEqualTo: phone)
          .where('createdAt',
              isGreaterThan: Timestamp.fromDate(startOfDay))
          .get();
      return snap.docs.length;
    } catch (e) {
      throw StateError('Индекс ёки сўров хатоси: $e');
    }
  }

  /// Янги эълон — муаллиф телефони нормализация қилинади.
  Future<void> addAd({
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
    final phone = _normPhone(authorPhone);
    if (phone.length < 9) {
      throw StateError('Телефон рақами нотўғри');
    }
    await _ads.add({
      'type': type,
      'text': text,
      if (title.isNotEmpty) 'title': title,
      if (priceText.isNotEmpty) 'priceText': priceText,
      'authorName': authorName.trim(),
      'authorPhone': phone,
      'address': address.trim(),
      'isUrgent': _urgentForType(type, isUrgent),
      'status': 'pending',
      'expiresAt': Timestamp.fromDate(expiresAt),
      'createdAt': FieldValue.serverTimestamp(),
      'editedAt': null,
    });
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
  }) async {
    final updates = <String, dynamic>{
      'text': text,
      'isUrgent': _urgentForType(type, isUrgent),
      'type': type,
      'editedAt': FieldValue.serverTimestamp(),
    };
    if (status != null) updates['status'] = status;
    if (title != null) updates['title'] = title;
    if (priceText != null) updates['priceText'] = priceText;
    await _ads.doc(adId).update(updates);
  }

  Future<void> updateAdStatus({
    required String adId,
    required String status,
  }) async {
    await _ads.doc(adId).update({
      'status': status,
      'moderatedAt': FieldValue.serverTimestamp(),
      'editedAt': FieldValue.serverTimestamp(),
    });
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

  /// Admin: эълонни ўчириш.
  Future<void> deleteAdAdmin(String adId) async {
    if (adId.isEmpty) return;
    await _ads.doc(adId).delete();
  }

  /// Эълонга шикоят.
  Future<void> addComplaint({
    required String adId,
    required String reason,
    String reporterPhone = '',
  }) async {
    final phone = _normPhone(reporterPhone);
    await _complaints.add({
      'adId': adId,
      'reason': reason,
      if (phone.isNotEmpty) 'reporterPhone': phone,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
