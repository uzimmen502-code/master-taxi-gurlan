import 'package:cloud_functions/cloud_functions.dart';

/// Nasab daraxti — global graf (Faza 1: poydevor).
/// `ensureMyTree` — komponent + "Men" tuguni + mavjud qarindoshlar migratsiyasi
/// (server-avtoritet, idempotent).
class TreeService {
  TreeService._();

  static final FirebaseFunctions _fn = FirebaseFunctions.instance;

  /// { ok, componentId, personId, migrated }
  static Future<Map<String, dynamic>> ensureMyTree() async {
    final res = await _fn.httpsCallable('ensureMyTree').call();
    return Map<String, dynamic>.from(res.data as Map);
  }
}
