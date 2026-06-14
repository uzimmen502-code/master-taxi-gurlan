import 'package:cloud_functions/cloud_functions.dart';

/// Web admin — haydovchi arizalarini Cloud Function orqali tasdiqlash/rad etish.
class AdminDriverRequestsService {
  Future<({String? error, List<String> warnings})> approve({
    required String adminPhone,
    required String requestId,
  }) async {
    const emptyWarnings = <String>[];
    try {
      final fn =
          FirebaseFunctions.instance.httpsCallable('approveDriverRequest');
      final res = await fn.call(<String, dynamic>{
        'adminPhone': adminPhone,
        'requestId': requestId,
      });
      final data = res.data;
      if (data is Map) {
        final raw = data['warnings'];
        if (raw is List) {
          return (
            error: null,
            warnings: raw.map((e) => e.toString()).toList(growable: false),
          );
        }
      }
      return (error: null, warnings: emptyWarnings);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found' || e.code == 'unimplemented') {
        return (
          error: 'Server funksiyasi deploy qilinmagan: approveDriverRequest',
          warnings: emptyWarnings,
        );
      }
      return (
        error: e.message ?? 'Tasdiqlanmadi (${e.code})',
        warnings: emptyWarnings,
      );
    } catch (e) {
      return (error: 'Xatolik: $e', warnings: emptyWarnings);
    }
  }

  Future<String?> reject({
    required String adminPhone,
    required String requestId,
    required String reason,
  }) async {
    try {
      final fn =
          FirebaseFunctions.instance.httpsCallable('rejectDriverRequest');
      await fn.call(<String, dynamic>{
        'adminPhone': adminPhone,
        'requestId': requestId,
        'reason': reason.trim(),
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found' || e.code == 'unimplemented') {
        return 'Server funksiyasi deploy qilinmagan: rejectDriverRequest';
      }
      return e.message ?? 'Rad etilmadi (${e.code})';
    } catch (e) {
      return 'Xatolik: $e';
    }
  }

  /// Marshrut / mahalliy / shaharlararo haydovchi bazasini tozalash.
  Future<({String? error, Map<String, dynamic>? stats})> resetTaxiDriversRegistry({
    required String adminPhone,
  }) async {
    try {
      final fn = FirebaseFunctions.instance
          .httpsCallable('adminResetTaxiDriversRegistry');
      final res = await fn.call(<String, dynamic>{
        'adminPhone': adminPhone,
        'confirmText': 'RESET_TAXI_DRIVERS',
      });
      final data = res.data;
      if (data is Map) {
        final stats = data['stats'];
        return (
          error: null,
          stats: stats is Map
              ? Map<String, dynamic>.from(stats)
              : <String, dynamic>{},
        );
      }
      return (error: null, stats: <String, dynamic>{});
    } on FirebaseFunctionsException catch (e) {
      return (error: e.message ?? e.code, stats: null);
    } catch (e) {
      return (error: 'Xatolik: $e', stats: null);
    }
  }

  /// Tasdiqlangan, lekin faol bo‘lmagan haydovchini ruxsatdan chiqarish.
  Future<String?> revoke({
    required String adminPhone,
    required String requestId,
    required String reason,
  }) async {
    try {
      final fn =
          FirebaseFunctions.instance.httpsCallable('revokeDriverApproval');
      await fn.call(<String, dynamic>{
        'adminPhone': adminPhone,
        'requestId': requestId,
        'reason': reason.trim(),
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found' || e.code == 'unimplemented') {
        return 'Server funksiyasi deploy qilinmagan: revokeDriverApproval';
      }
      return e.message ?? 'Chiqarib tashlanmadi (${e.code})';
    } catch (e) {
      return 'Xatolik: $e';
    }
  }
}
