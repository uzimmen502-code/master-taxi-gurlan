import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../utils/listing_moderation.dart';
import 'admin_callable.dart';

/// «Эълонлар модерацияси» (Бозорлар 2b): кутилаётган эълонлар ва `adminModerateListing` чақируви.
///
/// Ўқиш — тўғридан-тўғри Firestore (админ rules бўйича ўқий олади); ёзиш — ФАҚАТ сервер (callable, транзакция +
/// `admin_audit`, 41-банд). Сўровлар композит индекссиз: `status == 'pending'` (+ ads учун мавжуд
/// `type`+`status` сўрови — «Аралаш бозор» нишони билан бир хил), `limit 100`, тартиб клиентда.
class AdminListingModerationService {
  AdminListingModerationService({FirebaseFirestore? db, FirebaseFunctions? functions})
      : _db = db,
        _functions = functions;

  final FirebaseFirestore? _db;
  final FirebaseFunctions? _functions;

  FirebaseFirestore get _fs => _db ?? FirebaseFirestore.instance;

  Future<List<ListingModItem>> fetchPending(ListingModSource source) async {
    Query<Map<String, dynamic>> q = _fs.collection(source.collection);
    if (source == ListingModSource.ads) q = q.where('type', isEqualTo: 'cheap_product');
    final snap = await q.where('status', isEqualTo: 'pending').limit(kListingModPageLimit).get();
    return sortListingModItems([
      for (final doc in snap.docs)
        if (listingModMatchesSource(source, doc.data())) listingModItemFromRaw(source, doc.id, doc.data()),
    ]);
  }

  /// [approve] `false` — рад этиш; [reason] мажбурий (1..300; сервер ҳам текширади).
  Future<void> moderate({
    required ListingModSource source,
    required String id,
    required bool approve,
    String? reason,
  }) async {
    if (!approve && !listingRejectReasonValid(reason)) {
      throw const AdminCallableException('invalid-argument', 'REASON_REQUIRED', 'reason required');
    }
    await AdminCallable(_functions ?? FirebaseFunctions.instance).call('adminModerateListing', {
      'collection': source.collection,
      'id': id,
      'decision': approve ? 'approve' : 'reject',
      if (!approve) 'reason': reason!.trim(),
    });
  }
}
