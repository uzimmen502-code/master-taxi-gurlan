import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/features/profile/controllers/profile_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// `changeDevicePhone` CF хато кодлари → l10n калитлари (админ аудити O-16).
void main() {
  String key(String code, String? message) =>
      ProfileController.phoneChangeErrorKey(code, message);

  group('phoneChangeErrorKey', () {
    test('CF диагностик кодлари алоҳида матнга боғланади', () {
      expect(key('permission-denied', 'DEVICE_NOT_YOURS'),
          'profile_phone_change_not_yours');
      expect(key('failed-precondition', 'PHONE_BOUND_OTHER_DEVICE'),
          'profile_phone_change_bound_other');
      expect(key('failed-precondition', 'PHONE_HAS_ACCOUNT'),
          'profile_phone_change_has_account');
      expect(key('permission-denied', 'Phone login required'),
          'profile_phone_change_login_required');
      expect(key('unauthenticated', 'Auth required'),
          'profile_phone_change_login_required');
    });

    test('номаълум хато — умумий матн, хом код фойдаланувчига чиқмайди', () {
      expect(key('internal', 'INTERNAL'), 'profile_phone_change_failed');
      expect(key('not-found', 'Device binding not found'),
          'profile_phone_change_failed');
      expect(key('unavailable', null), 'profile_phone_change_failed');
    });

    test('ҳар бир калит уч тилда ҳам бор', () {
      const keys = [
        'profile_phone_change_not_yours',
        'profile_phone_change_bound_other',
        'profile_phone_change_has_account',
        'profile_phone_change_login_required',
        'profile_phone_change_failed',
      ];
      for (final lang in ['uz_Cyrl', 'uz_Latn', 'ru']) {
        final map = jsonDecode(
          File('assets/lang/$lang.json').readAsStringSync(),
        ) as Map<String, dynamic>;
        for (final k in keys) {
          expect((map[k] as String?)?.isNotEmpty, isTrue, reason: '$lang: $k');
        }
      }
    });
  });
}
