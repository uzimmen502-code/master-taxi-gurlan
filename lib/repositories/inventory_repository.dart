import 'package:cloud_firestore/cloud_firestore.dart';

/// Барча модулларнинг inventory'сини бошқарувчи репозиторий.
///
/// Учта collection ушлайди:
///   - `bread_products`     — тайёр нон (totalStock + soldToday)
///   - `extra_products`     — қўшимча маҳсулотлар (totalStock + soldToday)
///   - `food_inventory`     — тайёр овқат (FoodCatalog slug'и бўйича id)
///
/// `totalStock == 0` бўлса — **лимитсиз** (текширилмайди).
/// Ҳар куни тунда (00:00 Asia/Tashkent) `soldToday`ни нулга қайтариш —
/// `functions/index.js` ичида scheduled Cloud Function.
class InventoryRepository {
  InventoryRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _bread =>
      _db.collection('bread_products');
  CollectionReference<Map<String, dynamic>> get _extras =>
      _db.collection('extra_products');
  CollectionReference<Map<String, dynamic>> get _foodInv =>
      _db.collection('food_inventory');

  DocumentReference<Map<String, dynamic>> _refFor(
      InventoryKind kind, String id) {
    switch (kind) {
      case InventoryKind.bread:
        return _bread.doc(id);
      case InventoryKind.extra:
        return _extras.doc(id);
      case InventoryKind.food:
        return _foodInv.doc(id);
    }
  }

  /// Қолдиқни тезкор ўқиш (UI'да badge учун).
  Future<int> getRemaining(InventoryKind kind, String id) async {
    final doc = await _refFor(kind, id).get();
    if (!doc.exists) return 999999;
    final d = doc.data() ?? const <String, dynamic>{};
    final total = (d['totalStock'] as num?)?.toInt() ?? 0;
    final sold = (d['soldToday'] as num?)?.toInt() ?? 0;
    if (total <= 0) return 999999;
    final r = total - sold;
    return r < 0 ? 0 : r;
  }

  /// **Онлайн буюртма (илова):** `BalanceService.placeOrderWithWallet` — бир CFда
  /// order + омбор + кошелёк. Бу метод — оффлайн навбат / тест / махсус сценарийлар учун.
  ///
  /// Агар бирор маҳсулот етишмаса — `InsufficientStockException` отилади
  /// (барча декрементлар rollback қилинади).
  ///
  /// [orderData] — `orders/{id}`; [decrements] — омбор камайтиришлари.
  Future<DocumentReference<Map<String, dynamic>>> createOrderAtomically({
    required Map<String, dynamic> orderData,
    required List<StockChange> decrements,
  }) async {
    final ordersCol = _db.collection('orders');
    final orderRef = ordersCol.doc(); // ID олдиндан

    await _db.runTransaction((tx) async {
      // 1. Барча ҳужжатларни ўқиб қолдиқни текшириш.
      //    Транзакция qoidasi: avval barcha read, keyin write.
      final docs = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final c in decrements) {
        if (c.id.isEmpty || c.qty <= 0) continue;
        final ref = _refFor(c.kind, c.id);
        final snap = await tx.get(ref);
        docs['${c.kind.name}:${c.id}'] = snap;
      }

      // 2. Қолдиқларни текшириш — биринчи topgan etmасликда отамиз.
      final failures = <String>[];
      for (final c in decrements) {
        if (c.id.isEmpty || c.qty <= 0) continue;
        final snap = docs['${c.kind.name}:${c.id}'];
        if (snap == null) continue;
        if (!snap.exists) continue; // Yangi maxsulot bo'lsa, limitsiz
        final d = snap.data() ?? const <String, dynamic>{};
        final total = (d['totalStock'] as num?)?.toDouble() ?? 0;
        final sold = (d['soldToday'] as num?)?.toDouble() ?? 0;
        if (total <= 0) continue; // Лимитсиз
        final remaining = total - sold;
        if (remaining + 1e-9 < c.qty) {
          failures.add(
              '${c.label.isEmpty ? c.id : c.label}: керак ${c.qty}, қолди $remaining');
        }
      }
      if (failures.isNotEmpty) {
        throw InsufficientStockException(failures);
      }

      // 3. Ҳаммаси яхши — декрементлар.
      for (final c in decrements) {
        if (c.id.isEmpty || c.qty <= 0) continue;
        final snap = docs['${c.kind.name}:${c.id}'];
        if (snap == null) continue;
        if (!snap.exists) {
          // Йўқ ҳужжат бўлса яратамиз — `soldToday = qty` би сақлаймиз.
          // Бу баъзан Foodga мос келади (admin ҳали stock қўймаган).
          tx.set(snap.reference, {
            'totalStock': 0,
            'soldToday': c.qty,
          });
          continue;
        }
        tx.update(snap.reference, {
          'soldToday': FieldValue.increment(c.qty),
        });
      }

      // 4. Order ҳужжатини яратиш — server timestamp.
      final payload = Map<String, dynamic>.from(orderData);
      payload['createdAt'] = FieldValue.serverTimestamp();
      payload['status'] = payload['status'] ?? 'new';
      tx.set(orderRef, payload);
    });

    return orderRef;
  }

  /// Орderни бекор қилиш + inventory'ни **қайтариш**.
  ///
  /// Status `new`/`accepted`/`ready`да бўлганлар учунгина қайтарилади
  /// (бошқа холатларда қайтариш мантиқан тўғри эмас).
  Future<void> cancelOrderRestoringInventory({
    required String orderId,
    required String reason,
    required List<StockChange> increments,
  }) async {
    if (orderId.isEmpty) return;
    final orderRef = _db.collection('orders').doc(orderId);
    await _db.runTransaction((tx) async {
      final orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) return;
      final status = (orderSnap.data()?['status'] ?? '') as String;
      // Бу методда `delivered`га тегмаймиз — товар уже etkazildi.
      if (status == 'delivered' || status == 'rejected') return;

      // Inventory'ни ўз ўрнига qaytarish.
      for (final c in increments) {
        if (c.id.isEmpty || c.qty <= 0) continue;
        final ref = _refFor(c.kind, c.id);
        // Hujjat mavjudligini tekshiramiz (yangi maxsulot bo'lsa, qaytarish keraksiz).
        final snap = await tx.get(ref);
        if (!snap.exists) continue;
        final d = snap.data() ?? const <String, dynamic>{};
        final total = (d['totalStock'] as num?)?.toInt() ?? 0;
        if (total <= 0) continue;
        tx.update(ref, {
          'soldToday': FieldValue.increment(-c.qty),
        });
      }

      tx.update(orderRef, {
        'status': 'rejected',
        'rejectReason': reason,
        'rejectedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Админ панели: `food_inventory` бўйича жорий захира/сотилган (каталог билан бирлаштириш учун).
  Stream<Map<String, FoodInventoryDoc>> watchFoodInventory() {
    return _foodInv.snapshots().map((snap) {
      final m = <String, FoodInventoryDoc>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        m[doc.id] = FoodInventoryDoc(
          totalStock: (d['totalStock'] as num?)?.toInt() ?? 0,
          soldToday: (d['soldToday'] as num?)?.toInt() ?? 0,
        );
      }
      return m;
    });
  }

  /// Stocking helper — админ "Янги ҳужжат" яратганда керак.
  Future<void> setStock({
    required InventoryKind kind,
    required String id,
    int? totalStock,
    int? soldToday,
  }) async {
    if (id.isEmpty) return;
    final update = <String, Object?>{};
    if (totalStock != null) update['totalStock'] = totalStock;
    if (soldToday != null) update['soldToday'] = soldToday;
    if (update.isEmpty) return;
    await _refFor(kind, id).set(update, SetOptions(merge: true));
  }
}

/// `food_inventory/{id}` ҳужжати учун админ UI снапшоти.
class FoodInventoryDoc {
  const FoodInventoryDoc({
    required this.totalStock,
    required this.soldToday,
  });

  final int totalStock;
  final int soldToday;
}

/// Қайси collection: bread / extra / food.
enum InventoryKind { bread, extra, food }

/// Битта маҳсулот ўзгариши (кам/қўш) — миқдор `num` (дона бутун, кг/л каср).
class StockChange {
  const StockChange({
    required this.kind,
    required this.id,
    required this.qty,
    this.label = '',
  });

  final InventoryKind kind;

  /// `bread_products` ёки `extra_products`да — `firestoreId`.
  /// `food_inventory`да — FoodCatalog slug ёки сатр id.
  final String id;
  final num qty;

  /// Хабар учун ўқилишли ном — `"🌻 Кунжут"`.
  final String label;
}

/// Қолдиқ етишмаганда отиладиган exception.
class InsufficientStockException implements Exception {
  InsufficientStockException(this.details);
  final List<String> details;

  @override
  String toString() => 'InsufficientStockException(${details.join('; ')})';
}
