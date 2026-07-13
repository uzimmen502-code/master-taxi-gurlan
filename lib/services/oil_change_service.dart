import 'package:cloud_functions/cloud_functions.dart';

import '../core/utils/formatters.dart';
import '../models/oil_vehicle.dart';
import '../services/notification_service.dart';

/// Moy almashtirish — bonus va lokal push.
class OilChangeService {
  OilChangeService._();

  static final FirebaseFunctions _fn = FirebaseFunctions.instance;

  /// Profil mashinasi uchun bir martalik bonus (CF).
  static Future<Map<String, dynamic>> claimCarProfileBonus({
    String? uid,
  }) async {
    final callable = _fn.httpsCallable('claimCarProfileBonus');
    final result = await callable.call(<String, dynamic>{
      if (uid != null && uid.isNotEmpty) 'uid': canonicalPhoneId(uid),
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Keyingi muddatga lokal eslatma (7 kun oldin, agar bo‘lsa).
  static Future<void> scheduleDueReminder(OilVehicle vehicle) async {
    final due = vehicle.computeDueStatus();
    final next = due.nextDate;
    if (next == null) return;

    final id = vehicle.id.hashCode.abs() % 100000 + 42000;
    await NotificationService.instance.cancelReminder(id);

    final when = next.subtract(const Duration(days: 7));
    final title = 'Мой алмаштириш эслатмаси';
    final body = vehicle.hasOilTracking
        ? '${vehicle.displayTitle}: муддат яқинлашмоқда'
        : '${vehicle.displayTitle}: мой маълумотини тўлдиринг';

    if (when.isAfter(DateTime.now())) {
      await NotificationService.instance.scheduleReminder(
        id: id,
        title: title,
        body: body,
        when: when,
      );
    } else if (due.level != OilDueLevel.ok) {
      // Muddat yaqin/o‘tgan — ertaga ertalab eslatma.
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      await NotificationService.instance.scheduleReminder(
        id: id,
        title: title,
        body: body,
        when: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9),
      );
    }
  }
}
