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

  /// Tugunni telefon raqamiga ulash taklifi. { ok, alreadySent? }
  static Future<Map<String, dynamic>> sendLinkInvite({
    required String nodeId,
    required String toPhone,
  }) async {
    final res = await _fn.httpsCallable('sendTreeLinkInvite').call({
      'nodeId': nodeId,
      'toPhone': toPhone,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Taklifga javob. { ok, status, componentId?, personId? }
  static Future<Map<String, dynamic>> respondLinkInvite({
    required String inviteId,
    required bool accept,
  }) async {
    final res = await _fn.httpsCallable('respondTreeLinkInvite').call({
      'inviteId': inviteId,
      'accept': accept,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }
}
