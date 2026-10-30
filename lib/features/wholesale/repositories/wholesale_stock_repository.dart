import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../demand_offer/data/demand_repository.dart' show kDemandCoreRegion;
import '../models/wholesale_pack.dart';

/// Қадоқлар бўйича қолдиқ — `wholesale_stock/{productId}`.
///
/// Ўқиш — тўғридан-тўғри Firestore (Rules: ҳаммага). Ёзиш — ФАҚАТ
/// `setWholesaleStock` callable (functions_demand, europe-west1): эгалик
/// текшируви, транзакция ва тарих серверда (CLAUDE.md 18/22/41).
class WholesaleStockRepository {
  WholesaleStockRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _fn = functions;

  final FirebaseFirestore _db;
  final FirebaseFunctions? _fn;

  FirebaseFunctions get _functions =>
      _fn ?? FirebaseFunctions.instanceFor(region: kDemandCoreRegion);

  DocumentReference<Map<String, dynamic>> _doc(String productId) =>
      _db.collection('wholesale_stock').doc(productId);

  /// Битта маҳсулот тафсилоти учун (битта ҳужжат тинглагичи, экран
  /// ёпилганда ёпилади). Ҳужжат йўқ бўлса — бўш қолдиқ.
  Stream<WholesaleStock> watch(String productId) {
    if (productId.isEmpty) return Stream.value(WholesaleStock.empty);
    return _doc(productId)
        .snapshots()
        .map((s) => WholesaleStock.fromMap(s.data()));
  }

  Future<WholesaleStock> fetch(String productId) async {
    if (productId.isEmpty) return WholesaleStock.empty;
    final s = await _doc(productId).get();
    return WholesaleStock.fromMap(s.data());
  }

  /// Сотувчи қолдиқни ўрнатади (`{packId: qty}`). Бўш map — ҳеч нарса
  /// юборилмайди.
  Future<void> setStock(String productId, Map<String, int> stock) async {
    if (productId.isEmpty || stock.isEmpty) return;
    await _functions.httpsCallable('setWholesaleStock').call<Map<String, dynamic>>({
      'productId': productId,
      'stock': stock,
    });
  }
}
