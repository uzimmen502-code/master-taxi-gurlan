import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/formatters.dart';
import '../models/job_ad.dart';
import '../models/sell_offer_item.dart';
import '../models/sell_submission.dart';
import '../models/sell_offer_formatters.dart';
import '../services/sell_submission_service.dart';
import 'jobs_repository.dart';

/// `sell_submissions` — сотиш таклифлари.
class SellOffersRepository {
  SellOffersRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  static const int dailyPublicAdLimit = 10;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('sell_submissions');

  Stream<List<SellSubmission>> watchByUser(String userId, {int limit = 20}) {
    final uid = phoneDigits(userId);
    if (uid.length < 9) return Stream.value(const []);
    return _col
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(SellSubmission.fromDoc).toList(growable: false));
  }

  Stream<List<SellSubmission>> watchForAdmin({int limit = 200}) {
    return _col
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(SellSubmission.fromDoc).toList(growable: false));
  }

  Future<DocumentReference<Map<String, dynamic>>> create(
    SellSubmission draft,
  ) async {
    return createWithPickup(draft, {});
  }

  Future<DocumentReference<Map<String, dynamic>>> createWithPickup(
    SellSubmission draft,
    Map<String, dynamic> pickupFields,
  ) async {
    final submissionId = await SellSubmissionService.submit(
      items: draft.items.map((e) => e.toMap()).toList(growable: false),
      userName: draft.userName,
      pickupAddress: (pickupFields['pickupAddress'] as String?) ?? draft.pickupAddress,
      pickupLat: (pickupFields['pickupLat'] as num?)?.toDouble() ?? draft.pickupLat,
      pickupLng: (pickupFields['pickupLng'] as num?)?.toDouble() ?? draft.pickupLng,
      pickupNote: draft.pickupNote,
      pickupDetails: pickupFields['pickupDetails'] is Map
          ? Map<String, dynamic>.from(pickupFields['pickupDetails'] as Map)
          : null,
    );
    return _col.doc(submissionId);
  }

  /// «Сотаман» — `ads` коллекциясига (moderatsiya: pending).
  Future<void> publishAsPublicAd({
    required JobsRepository jobsRepo,
    required List<SellOfferItem> items,
    required String authorName,
    required String authorPhone,
    required String address,
  }) async {
    if (items.isEmpty) return;
    final days = AdKind.sell.expiresInDays;
    await jobsRepo.addAd(
      type: AdKind.sell.key,
      title: SellOfferFormatters.adTitle(items),
      text: SellOfferFormatters.adBody(items),
      priceText: SellOfferFormatters.adPriceSummary(items),
      authorName: authorName,
      authorPhone: authorPhone,
      address: address,
      isUrgent: false,
      expiresAt: DateTime.now().add(Duration(days: days)),
    );
  }

  Future<void> updateStatus({
    required String id,
    required String status,
    String? adminNote,
  }) async {
    if (id.isEmpty) return;
    final patch = <String, dynamic>{
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (adminNote != null) patch['adminNote'] = adminNote;
    await _col.doc(id).update(patch);
  }

  Future<void> forwardToUsers({
    required String id,
    required String audience,
    List<String> targetUserIds = const [],
    String adminNote = '',
  }) async {
    if (id.isEmpty) return;
    final normalized = targetUserIds
        .map(phoneDigits)
        .where((p) => p.length >= 9)
        .toSet()
        .toList(growable: false);
    if (audience == 'selected' && normalized.isEmpty) {
      throw StateError('Kamida bitta telefon kiriting');
    }
    final patch = <String, dynamic>{
      'forwardAudience': audience,
      'forwardedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (audience == 'selected') {
      patch['visibleToUserIds'] = normalized;
    }
    if (adminNote.trim().isNotEmpty) {
      patch['adminNote'] = adminNote.trim();
    }
    await _col.doc(id).update(patch);
  }
}
