import 'package:cloud_functions/cloud_functions.dart';

/// Йiғib оlish vazifalari — admin Cloud Functions.
class CollectionService {
  CollectionService._();

  static final FirebaseFunctions _fn = FirebaseFunctions.instance;

  static Future<({String taskId, int totalValue})> createCollectionTask({
    required String adminPhone,
    required String submissionId,
    required List<Map<String, dynamic>> items,
    required String courierPhone,
  }) async {
    final result =
        await _fn.httpsCallable('adminCreateCollectionTask').call({
      'adminPhone': adminPhone,
      'submissionId': submissionId,
      'items': items,
      'courierPhone': courierPhone,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return (
      taskId: (data['taskId'] ?? '') as String,
      totalValue: (data['totalValue'] as num?)?.toInt() ?? 0,
    );
  }

  /// Курьер: йиғишни якунлаш — кошелёк кредити + омбор + далолатнома (B3).
  /// Қайтаради: { ok, V, cashGiven, walletCredit, newBalance }.
  static Future<Map<String, dynamic>> finalizeCollection({
    required String courierPhone,
    required String taskId,
    required List<Map<String, dynamic>> items,
    required int cashGiven,
  }) async {
    final result =
        await _fn.httpsCallable('courierFinalizeCollection').call({
      'courierPhone': courierPhone,
      'taskId': taskId,
      'items': items,
      'cashGiven': cashGiven,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Курьер: йиғиб оlish манзилига етиб келди — қўнғироқли хабар.
  static Future<void> markCollectionArrived({
    required String courierPhone,
    required String taskId,
  }) async {
    await _fn.httpsCallable('courierMarkCollectionArrived').call({
      'courierPhone': courierPhone,
      'taskId': taskId,
    });
  }

  /// Админ: омбор (`warehouse_stock`) ҳолати — read-only.
  /// Қайтаради: [{ code, label, unit, quantity, updatedAt(ms or null) }].
  static Future<List<WarehouseStockItem>> getWarehouseStock({
    required String adminPhone,
  }) async {
    final result = await _fn.httpsCallable('adminGetWarehouseStock').call({
      'adminPhone': adminPhone,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final raw = (data['items'] as List?) ?? const [];
    return raw
        .map((e) => WarehouseStockItem.fromMap(
              Map<String, dynamic>.from(e as Map),
            ))
        .toList();
  }
}

/// Омбордаги битта маҳсулот қолдиғи.
class WarehouseStockItem {
  const WarehouseStockItem({
    required this.code,
    required this.label,
    required this.unit,
    required this.quantity,
    this.updatedAt,
  });

  final String code;
  final String label;
  final String unit;
  final num quantity;
  final DateTime? updatedAt;

  factory WarehouseStockItem.fromMap(Map<String, dynamic> m) {
    final ms = (m['updatedAt'] as num?)?.toInt();
    return WarehouseStockItem(
      code: (m['code'] ?? '') as String,
      label: (m['label'] ?? '') as String,
      unit: (m['unit'] ?? '') as String,
      quantity: (m['quantity'] as num?) ?? 0,
      updatedAt:
          ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
    );
  }
}
