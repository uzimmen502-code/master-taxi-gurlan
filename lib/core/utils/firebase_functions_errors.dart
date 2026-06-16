import 'package:cloud_functions/cloud_functions.dart';

/// Firebase callable xatolari uchun foydalanuvchiga tushunarli matn.
String firebaseFunctionsUserMessage(FirebaseFunctionsException e) {
  final detail = e.message?.trim();
  if (detail != null &&
      detail.isNotEmpty &&
      detail != 'INTERNAL' &&
      e.code != 'unavailable') {
    return detail;
  }

  return switch (e.code) {
    'unavailable' =>
      'Интернет уланиши йўқ ёки серверга ulanib bo\'lmadi. Internetni yoqing va qayta urinib ko\'ring.',
    'deadline-exceeded' => 'Сервер жавоб bermadi. Бир oz muddatdan keyin qayta urinib ko\'ring.',
    'resource-exhausted' => 'Juda ko\'p urinish. Biroz kutib qayta urinib ko\'ring.',
    'internal' => 'Server xatosi. Keyinroq qayta urinib ko\'ring.',
    'not-found' => 'Код сўрови топилмади',
    'permission-denied' => 'Код нотўғри',
    'failed-precondition' => 'Қурилма ёки рақам мос эмас',
    'invalid-argument' => 'Нотўғри маълумот',
    _ => 'Хатолик: ${e.code}',
  };
}
