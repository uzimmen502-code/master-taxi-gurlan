import 'package:cloud_functions/cloud_functions.dart';

/// Tanishuv (dating) — Cloud Functions orqali server-avtoritet amallar.
class DatingService {
  DatingService._();

  static final FirebaseFunctions _fn = FirebaseFunctions.instance;

  static Future<void> saveProfile(Map<String, dynamic> data) async {
    await _fn.httpsCallable('saveDatingProfile').call(data);
  }

  static Future<void> setActive(bool active) async {
    await _fn.httpsCallable('setDatingActive').call({'active': active});
  }

  static Future<void> setAgePreference({
    required int minAge,
    required int maxAge,
  }) async {
    await _fn.httpsCallable('setDatingAgePreference').call({
      'minAge': minAge,
      'maxAge': maxAge,
    });
  }

  static Future<void> deleteProfile() async {
    await _fn.httpsCallable('deleteDatingProfile').call();
  }

  /// { ok, matched, matchId?, alreadySent? }
  static Future<Map<String, dynamic>> sendInterest(String toUserId) async {
    final res =
        await _fn.httpsCallable('sendDatingInterest').call({'toUserId': toUserId});
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// { ok, status, matchId? }
  static Future<Map<String, dynamic>> respondInterest(
      String interestId, bool accept) async {
    final res = await _fn.httpsCallable('respondDatingInterest').call({
      'interestId': interestId,
      'accept': accept,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<void> adminModerate({
    required String userId,
    required String action, // approve|reject|block
    String reason = '',
  }) async {
    await _fn.httpsCallable('adminModerateDatingProfile').call({
      'userId': userId,
      'action': action,
      'reason': reason,
    });
  }

  static Future<void> setAutoApprove({
    required String adminPhone,
    required bool enabled,
  }) async {
    await _fn.httpsCallable('adminSetDatingAutoApprove').call({
      'adminPhone': adminPhone,
      'enabled': enabled,
    });
  }
}
