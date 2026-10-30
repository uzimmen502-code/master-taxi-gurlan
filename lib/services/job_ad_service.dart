import '../core/service_config_holder.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Иш топ — CF-only яратиш / шикоят.
class JobAdService {
  JobAdService._();

  static final FirebaseFunctions _fn = FirebaseFunctions.instance;

  /// Эълон яратиш.
  ///
  /// Эга номи ва ҳудуд ёрлиғи СЕРВЕРДА профилдан олинади (мижозга ишонилмайди,
  /// уй манзили ҳам ошкор бўлмайди) — шунинг учун `authorName`/`address`
  /// юборилмайди. [requestId] — қайта юборишда эълон такрорланмаслиги учун
  /// (сервер бир хил `requestId` га бир хил эълонни қайтаради).
  static Future<({String adId, String status})> submitAd({
    required String type,
    required String text,
    String title = '',
    String priceText = '',
    bool isUrgent = false,
    String requestId = '',
  }) async {
    final res = await _fn.httpsCallable('submitJobAd').call({
      ...ServiceConfigHolder.moduleGeoField,
      'type': type,
      'text': text,
      'title': title,
      if (priceText.isNotEmpty) 'priceText': priceText,
      'isUrgent': isUrgent,
      if (requestId.isNotEmpty) 'requestId': requestId,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    return (
      adId: (data['adId'] ?? '') as String,
      status: (data['status'] ?? '') as String,
    );
  }

  static Future<String> submitComplaint({
    required String adId,
    required String reason,
  }) async {
    final res = await _fn.httpsCallable('submitJobComplaint').call({
      'adId': adId,
      'reason': reason,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    return (data['complaintId'] ?? '') as String;
  }
}
