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

  /// Komponent ichida ikki tugunni birlashtirish (dedup). { ok, keepId }
  static Future<Map<String, dynamic>> mergeTreePersons({
    required String keepId,
    required String mergeId,
  }) async {
    final res = await _fn.httpsCallable('mergeTreePersons').call({
      'keepId': keepId,
      'mergeId': mergeId,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// { ok, personId }
  static Future<Map<String, dynamic>> addRelativePerson({
    required String fullName,
    String firstName = '',
    String lastName = '',
    String patronymic = '',
    String gender = '',
    String photoUrl = '',
    String photoPath = '',
    String phone = '',
    String address = '',
    String relationDegree = '',
    String side = '',
    String notes = '',
    DateTime? birthDate,
    String? fatherId,
    String? motherId,
    String? spouseId,
  }) async {
    final res = await _fn.httpsCallable('addRelativePerson').call({
      'fullName': fullName,
      'firstName': firstName,
      'lastName': lastName,
      'patronymic': patronymic,
      'gender': gender,
      'photoUrl': photoUrl,
      'photoPath': photoPath,
      'phone': phone,
      'address': address,
      'relationDegree': relationDegree,
      'side': side,
      'notes': notes,
      'birthDateMs': birthDate?.millisecondsSinceEpoch,
      'fatherId': fatherId,
      'motherId': motherId,
      'spouseId': spouseId,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// { ok, alreadyDeleted? }
  static Future<Map<String, dynamic>> deleteRelativePerson({
    required String personId,
  }) async {
    final res = await _fn.httpsCallable('deleteRelativePerson').call({
      'personId': personId,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Daraxt tugunini yaratish/tahrirlash (umumiy tahrir). { ok, nodeId }
  /// [nodeId] bo'sh bo'lsa — yangi tugun yaratiladi.
  static Future<Map<String, dynamic>> saveNode({
    String nodeId = '',
    required String fullName,
    String firstName = '',
    String lastName = '',
    String patronymic = '',
    String gender = '',
    String photoUrl = '',
    String photoPath = '',
    DateTime? birthDate,
    String? fatherId,
    String? motherId,
    String? spouseId,
  }) async {
    final res = await _fn.httpsCallable('saveTreeNode').call({
      'nodeId': nodeId,
      'fullName': fullName,
      'firstName': firstName,
      'lastName': lastName,
      'patronymic': patronymic,
      'gender': gender,
      'photoUrl': photoUrl,
      'photoPath': photoPath,
      'birthDateMs': birthDate?.millisecondsSinceEpoch,
      'fatherId': fatherId,
      'motherId': motherId,
      'spouseId': spouseId,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Tarixdagi amalni qaytarish (Undo). { ok }
  static Future<Map<String, dynamic>> undoOperation(String historyId) async {
    final res = await _fn.httpsCallable('undoTreeOperation').call({
      'historyId': historyId,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }
}
