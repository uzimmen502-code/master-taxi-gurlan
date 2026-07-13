import 'package:cloud_functions/cloud_functions.dart';

/// Админ мой каталоги — Cloud Functions (Firestore `isAdmin()` эмас).
class AdminOilCatalogService {
  AdminOilCatalogService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<String> upsert({
    required String adminPhone,
    String? id,
    required String name,
    required int price,
    String meta = '',
    String reason = '',
    String imageUrl = '',
    Map<String, String> specs = const {},
    int sortOrder = 0,
    bool active = true,
    bool isFilter = false,
    bool must = false,
    bool dust = false,
    bool gas = false,
  }) async {
    try {
      final result =
          await _functions.httpsCallable('adminUpsertOilCatalogItem').call({
        'adminPhone': adminPhone,
        if (id != null && id.isNotEmpty) 'id': id,
        'name': name,
        'price': price,
        'meta': meta,
        'reason': reason,
        'imageUrl': imageUrl,
        'specs': specs,
        'sortOrder': sortOrder,
        'active': active,
        'kind': isFilter ? 'filter' : 'oil',
        'must': must,
        'dust': dust,
        'gas': gas,
      });
      final data = result.data;
      if (data is Map && data['id'] != null) return '${data['id']}';
      return id ?? '';
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? e.code);
    }
  }

  Future<void> delete({
    required String adminPhone,
    required String id,
  }) async {
    try {
      await _functions.httpsCallable('adminDeleteOilCatalogItem').call({
        'adminPhone': adminPhone,
        'id': id,
      });
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? e.code);
    }
  }

  Future<int> seed({
    required String adminPhone,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final result =
          await _functions.httpsCallable('adminSeedOilCatalog').call({
        'adminPhone': adminPhone,
        'items': items,
      });
      final data = result.data;
      if (data is Map) {
        return int.tryParse('${data['seeded'] ?? 0}') ?? 0;
      }
      return 0;
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? e.code);
    }
  }
}
