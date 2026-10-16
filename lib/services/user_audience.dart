import 'package:shared_preferences/shared_preferences.dart';

import 'user_role_sync.dart';

/// Фойдаланувчи қайси АУДИТОРИЯга киради (янгиликлар, бош саҳифа тасмаси,
/// push йўналтириш) — ҳайдовчилик ҲУҚУҚДАН (capability), эски `users.role`
/// белгисидан эмас (эга, 2026-10-16: «ҳайдовчи роли» тушунчасидан кетиш).
///
/// Сабаб: янги оқимда ҳайдовчи ўзи ёқади ва `users.role` ЯНГИЛАНМАЙДИ,
/// шунинг учун `role == 'driver'` бундай ҳайдовчини "ҳайдовчи эмас" деб
/// кўрсатар ва `UserRoleSync` маҳаллий `driver` ни серверданги `user` билан
/// босиб ёзиб юборар эди.
///
/// Манба — `DriverRoles.isDriver` (`provider_capabilities`); бош саҳифа уни
/// очилганда ва ҳар ўзгаришдан кейин янгилайди ([saveTaxiDriver]). Белги
/// фақат ҲУҚУҚ ҳолати ҲАҚИҚАТАН ўқилганда ёзилади.
class UserAudience {
  UserAudience._();

  /// `SharedPreferences` калити — capability'дан келган кэш.
  static const prefTaxiDriver = 'is_taxi_driver';

  static Future<void> saveTaxiDriver(bool isDriver) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefTaxiDriver, isDriver);
    } catch (_) {
      // Кэш ёзилмаса асосий оқим тўхтамайди.
    }
  }

  /// Соф функция (тест учун): `user_role` (админлар) ва `is_taxi_driver`.
  ///
  /// Админ/диспетчер ҳамиша ўз роли билан; сўнг ҳайдовчи; сўнг эски
  /// PIN-курьер (ўтиш даври); қолган ҳамма — `user`.
  static String resolve({required String storedRole, required bool taxiDriver}) {
    final role = storedRole.trim().toLowerCase();
    if (UserRoleSync.isPrivileged(role)) return role;
    if (taxiDriver) return 'driver';
    if (role == 'courier') return 'courier';
    return 'user';
  }

  static String fromPrefs(SharedPreferences prefs) => resolve(
        storedRole: prefs.getString('user_role') ?? 'user',
        taxiDriver: prefs.getBool(prefTaxiDriver) ?? false,
      );

  static Future<String> current() async {
    try {
      return fromPrefs(await SharedPreferences.getInstance());
    } catch (_) {
      return 'user';
    }
  }

  /// Ҳозир ҳайдовчи ҳуқуқи борми (админ бўлса ҳам) — push йўналтириш учун.
  static bool taxiDriverFrom(SharedPreferences prefs) =>
      prefs.getBool(prefTaxiDriver) ?? false;
}
