import 'package:cloud_functions/cloud_functions.dart';

/// Firebase callable xatolari uchun foydalanuvchiga tushunarli matn.
String firebaseFunctionsUserMessage(FirebaseFunctionsException e) {
  final code = e.code.trim().toLowerCase();
  final detail = e.message?.trim();
  final detailUpper = (detail ?? '').toUpperCase();

  // Infrastructure / transport codes — never surface raw DEADLINE_EXCEEDED etc.
  if (code == 'deadline-exceeded' ||
      detailUpper.contains('DEADLINE_EXCEEDED')) {
    return 'Сервер жавоб бермади. Бироздан кейин қайта уриниб кўринг.';
  }
  if (code == 'unavailable') {
    return 'Интернет уланиши йўқ ёки серверга уланиб бўлмади. '
        'Интернетни ёқинг ва қайта уриниб кўринг.';
  }
  if (code == 'resource-exhausted') {
    return 'Жуда кўп уриниш. Бироз кутиб қайта уриниб кўринг.';
  }

  // Prefer server-provided human message when it is not a raw status code.
  if (detail != null &&
      detail.isNotEmpty &&
      detail != 'INTERNAL' &&
      !_looksLikeRawErrorCode(detail)) {
    return detail;
  }

  return switch (code) {
    'internal' => 'Сервер хатоси. Кейинроқ қайта уриниб кўринг.',
    'not-found' => 'Код сўрови топилмади',
    'permission-denied' => 'Код нотўғри',
    'failed-precondition' => 'Қурилма ёки рақам мос эмас',
    'invalid-argument' => 'Нотўғри маълумот',
    _ => 'Хатолик юз берди. Қайта уриниб кўринг.',
  };
}

bool _looksLikeRawErrorCode(String value) {
  // e.g. DEADLINE_EXCEEDED, INTERNAL, UNAVAILABLE
  return RegExp(r'^[A-Z][A-Z0-9_]+$').hasMatch(value.trim());
}
