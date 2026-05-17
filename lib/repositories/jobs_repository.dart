import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/job_ad.dart';

/// `ads` ва `complaints` collection'лар билан ишлайди.
class JobsRepository {
  JobsRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _ads => _db.collection('ads');
  CollectionReference<Map<String, dynamic>> get _complaints =>
      _db.collection('complaints');

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
  ///
  /// Firestore'нинг `whereIn` лимити — 30 элементгача, бизга 3 та етади.
  Stream<List<JobAd>> watchAllActive({int limit = 100}) {
    return _ads
        .where('type', whereIn: ['work', 'service', 'ad'])
        .where('status', isEqualTo: 'active')
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(JobAd.fromDoc).toList(growable: false));
  }

  /// Admin panel учун: барча эълонлар, шу жумладан тасдиқ кутяпганлари.
  Stream<List<JobAd>> watchAllForAdmin({int limit = 300}) {
    return _ads
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(JobAd.fromDoc).toList(growable: false));
  }

  /// Бугун (00:00 дан кейин) ушбу муаллиф томонидан қўшилган эълонлар сони.
  /// Кунлик лимит 5 та учун керак.
  Future<int> dailyCountByAuthor(String authorPhone) async {
    if (authorPhone.isEmpty) return 0;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    try {
      final snap = await _ads
          .where('authorPhone', isEqualTo: authorPhone)
          .where('createdAt',
              isGreaterThan: Timestamp.fromDate(startOfDay))
          .get();
      return snap.docs.length;
    } catch (_) {
      return 0;
    }
  }

  /// Янги эълон қўшиш. `type`: `work` | `service` | `ad`.
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
    await _ads.add({
      'type': type,
      'text': text,
      if (title.isNotEmpty) 'title': title,
      if (priceText.isNotEmpty) 'priceText': priceText,
      'authorName': authorName,
      'authorPhone': authorPhone,
      'address': address,
      'isUrgent': type == 'work' ? isUrgent : false,
      'status': 'pending',
      'expiresAt': Timestamp.fromDate(expiresAt),
      'createdAt': FieldValue.serverTimestamp(),
      'editedAt': null,
    });
  }

  /// Эълонни таҳрирлаш.
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
      'isUrgent': type == 'work' ? isUrgent : false,
      'editedAt': FieldValue.serverTimestamp(),
    };
    if (status != null) updates['status'] = status;
    if (title != null) updates['title'] = title;
    if (priceText != null) updates['priceText'] = priceText;
    await _ads.doc(adId).update(updates);
  }

  /// Admin moderation: pending/active/completed/blocked статусларини ўзгартириш.
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

  /// Эълонга шикоят қўшиш.
  Future<void> addComplaint({
    required String adId,
    required String reason,
  }) async {
    await _complaints.add({
      'adId': adId,
      'reason': reason,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
