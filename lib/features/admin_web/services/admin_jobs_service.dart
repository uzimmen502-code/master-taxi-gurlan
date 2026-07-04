import 'package:cloud_functions/cloud_functions.dart';

/// Admin web — Иш топ e'lonlari (Cloud Functions, Firestore rules emas).
class AdminJobsService {
  AdminJobsService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<void> deleteAd({
    required String adminPhone,
    required String adId,
  }) async {
    await _call('adminDeleteJobAd', {
      'adminPhone': adminPhone,
      'adId': adId,
    });
  }

  Future<void> updateAdStatus({
    required String adminPhone,
    required String adId,
    required String status,
  }) async {
    await _call('adminUpdateJobAdStatus', {
      'adminPhone': adminPhone,
      'adId': adId,
      'status': status,
    });
  }

  Future<void> updateAd({
    required String adminPhone,
    required String adId,
    required String text,
    required String type,
    required bool isUrgent,
    String? status,
    String? title,
    String? priceText,
    String? address,
    DateTime? expiresAt,
    String? adminNote,
  }) async {
    await _call('adminUpdateJobAd', {
      'adminPhone': adminPhone,
      'adId': adId,
      'text': text,
      'type': type,
      'isUrgent': isUrgent,
      if (status != null) 'status': status,
      if (title != null) 'title': title,
      if (priceText != null) 'priceText': priceText,
      if (address != null) 'address': address,
      if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
      if (adminNote != null) 'adminNote': adminNote,
    });
  }

  Future<void> resolveComplaint({
    required String adminPhone,
    required String complaintId,
  }) async {
    await _call('adminResolveJobComplaint', {
      'adminPhone': adminPhone,
      'complaintId': complaintId,
    });
  }

  Future<void> _call(String name, Map<String, dynamic> data) async {
    try {
      await _functions.httpsCallable(name).call(data);
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? e.code);
    }
  }
}
