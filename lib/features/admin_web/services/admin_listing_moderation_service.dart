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
    // «Рад этилганлар» — `status == 'rejected'` (композит индекссиз; тартиб клиентда).
    final snap = await q.where('status', isEqualTo: source.status).limit(kListingModPageLimit).get();
    return sortListingModItems([
      for (final doc in snap.docs)
        if (listingModMatchesSource(source, doc.data())) listingModItemFromRaw(source, doc.id, doc.data()),
    ]);
  }

  /// Бозор бўлимлари (`taxonomy/markets`, ҳамма ўқий олади). Ҳужжат йўқ — бўш.
  Future<Map<String, List<ListingModCategory>>> fetchMarketCategories() async {
    final snap = await _fs.collection('taxonomy').doc('markets').get();
    return listingModCategoriesFromTaxonomy(snap.data());
  }

  /// [approve] `false` — рад этиш; [reason] мажбурий (1..300; сервер ҳам текширади).
  /// [edits] — «тузатиб тасдиқлаш» (фақат approve + tv_shop_items; бўш — юборилмайди).
  Future<void> moderate({
    required ListingModSource source,
    required String id,
    required bool approve,
    String? reason,
    Map<String, Object?>? edits,
  }) async {
    if (!approve && !listingRejectReasonValid(reason)) {
      throw const AdminCallableException('invalid-argument', 'REASON_REQUIRED', 'reason required');
    }
    final hasEdits = edits != null && edits.isNotEmpty;
    if (hasEdits && !approve) {
      throw const AdminCallableException('invalid-argument', 'EDITS_REQUIRE_APPROVE', 'edits require approve');
    }
    if (hasEdits && !source.editable) {
      throw const AdminCallableException('invalid-argument', 'EDITS_NOT_SUPPORTED', 'edits not supported');
    }
    await AdminCallable(_functions ?? FirebaseFunctions.instance)
        .call('adminModerateListing', listingModPayload(source: source, id: id, approve: approve, reason: reason, edits: edits));
  }
}

/// `adminModerateListing` маълумоти (тестланади).
Map<String, Object?> listingModPayload({
  required ListingModSource source,
  required String id,
  required bool approve,
  String? reason,
  Map<String, Object?>? edits,
}) =>
    {
      'collection': source.collection,
      'id': id,
      'decision': approve ? 'approve' : 'reject',
      if (!approve) 'reason': (reason ?? '').trim(),
      if (approve && edits != null && edits.isNotEmpty) 'edits': edits,
    };
