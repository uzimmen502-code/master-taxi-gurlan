import 'package:cloud_functions/cloud_functions.dart';

/// Харидор шикояти — ресторан, таом, кўчмас мулк эълони (`submitContentComplaint`, functions/content_complaints.js).
/// Барча текширув (кўринадими, эгасими, сабаб, такрор, кунлик чеклов) СЕРВЕРДА; бу ерда фақат чақирув (18/44-банд).
class ContentComplaintRepository {
  ContentComplaintRepository({FirebaseFunctions? functions}) : _fns = functions;

  final FirebaseFunctions? _fns;

  /// [targetType]: `restaurant` | `restaurant_item` | `realty_listing`; таомда [restaurantId] шарт.
  /// [reason] — [contentComplaintReasons] даги код. Хато — [FirebaseFunctionsException] (`details.code`).
  Future<void> submit({
    required String targetType,
    required String targetId,
    String restaurantId = '',
    required String reason,
    String comment = '',
  }) async {
    await (_fns ?? FirebaseFunctions.instance).httpsCallable('submitContentComplaint').call<Object?>({
      'targetType': targetType,
      'targetId': targetId,
      if (restaurantId.isNotEmpty) 'restaurantId': restaurantId,
      'reason': reason,
      if (comment.isNotEmpty) 'comment': comment,
    });
  }
}
