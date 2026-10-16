import 'package:ava_gurlan/models/driver_roles.dart';
import 'package:ava_gurlan/services/user_audience.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Аудитория (янгиликлар, тасма, push йўналтириш) — ҳайдовчилик ҲУҚУҚДАН
/// (эга, 2026-10-16). Эски `users.role == 'driver'` белгисига боғланмайди.
void main() {
  group('UserAudience.resolve', () {
    test('оддий фойдаланувчи — user', () {
      expect(UserAudience.resolve(storedRole: 'user', taxiDriver: false), 'user');
      expect(UserAudience.resolve(storedRole: '', taxiDriver: false), 'user');
    });

    test('capability ҳайдовчиси — driver, `user_role` user бўлса ҳам (янги оқим)', () {
      expect(UserAudience.resolve(storedRole: 'user', taxiDriver: true), 'driver');
    });

    test('ЭСКИ маҳаллий `driver` белгиси ҳуқуқсиз ҳайдовчи ҚИЛМАЙДИ', () {
      expect(UserAudience.resolve(storedRole: 'driver', taxiDriver: false), 'user');
    });

    test('админ/диспетчер ўз роли билан қолади (ҳайдовчи бўлса ҳам)', () {
      for (final r in const ['admin', 'superadmin', 'dispatcher']) {
        expect(UserAudience.resolve(storedRole: r, taxiDriver: true), r, reason: r);
        expect(UserAudience.resolve(storedRole: r, taxiDriver: false), r, reason: r);
      }
      expect(UserAudience.resolve(storedRole: ' Admin ', taxiDriver: false), 'admin');
    });

    test('ўтиш даври: эски PIN-курьер courier; ҳайдовчи ҳуқуқи устун', () {
      expect(UserAudience.resolve(storedRole: 'courier', taxiDriver: false), 'courier');
      expect(UserAudience.resolve(storedRole: 'courier', taxiDriver: true), 'driver');
    });
  });

  group('UserAudience (SharedPreferences)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('бошланғич ҳолат: белги йўқ — ҳайдовчи эмас', () async {
      final p = await SharedPreferences.getInstance();
      expect(UserAudience.taxiDriverFrom(p), isFalse);
      expect(await UserAudience.current(), 'user');
    });

    test('saveTaxiDriver(true/false) — current() ва taxiDriverFrom мос', () async {
      await UserAudience.saveTaxiDriver(true);
      final p = await SharedPreferences.getInstance();
      expect(UserAudience.taxiDriverFrom(p), isTrue);
      expect(await UserAudience.current(), 'driver');
      await UserAudience.saveTaxiDriver(false);
      expect(UserAudience.taxiDriverFrom(p), isFalse);
      expect(await UserAudience.current(), 'user');
    });

    test('`user_role: driver` (қолдиқ) + белги йўқ → user; белги бор → driver', () async {
      SharedPreferences.setMockInitialValues({'user_role': 'driver'});
      expect(await UserAudience.current(), 'user');
      SharedPreferences.setMockInitialValues({
        'user_role': 'user',
        UserAudience.prefTaxiDriver: true,
      });
      expect(await UserAudience.current(), 'driver');
    });

    test('админ роли ҳайдовчи белгисидан устун', () async {
      SharedPreferences.setMockInitialValues({
        'user_role': 'superadmin',
        UserAudience.prefTaxiDriver: true,
      });
      expect(await UserAudience.current(), 'superadmin');
      final p = await SharedPreferences.getInstance();
      // push йўналтириш учун ҳайдовчилик алоҳида ўқилади
      expect(UserAudience.taxiDriverFrom(p), isTrue);
    });
  });

  group('DriverRoles.known', () {
    test('ҳолат ўқилмаган (хато) бўлса known=false — "ҳайдовчи эмас" деб ёзилмайди', () {
      expect(DriverRoles.none.known, isFalse);
      expect(const DriverRoles(courierOnline: true).known, isFalse);
    });

    test('ўқилган ҳолат known=true ва isDriver туридан келади', () {
      const notDriver = DriverRoles(known: true);
      const driver = DriverRoles(types: ['local'], known: true);
      expect(notDriver.known && !notDriver.isDriver, isTrue);
      expect(driver.known && driver.isDriver, isTrue);
    });
  });
}
