import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/core/utils/user_error.dart';

/// Foydalanuvchiga xom xato matni chiqmasligi (CLAUDE.md §25): xato -> l10n kaliti.
void main() {
  FirebaseFunctionsException fn(String code, [String message = 'x']) =>
      FirebaseFunctionsException(code: code, message: message);

  group('userErrorKeyPure — callable kodlari', () {
    test('tarmoq / vaqt / limit / auth / ruxsat / topilmadi / server', () {
      expect(userErrorKeyPure(fn('unavailable')), 'err_network');
      expect(userErrorKeyPure(fn('deadline-exceeded')), 'err_timeout');
      expect(userErrorKeyPure(fn('resource-exhausted')), 'err_too_many');
      expect(userErrorKeyPure(fn('unauthenticated')), 'err_auth');
      expect(userErrorKeyPure(fn('permission-denied')), 'err_permission');
      expect(userErrorKeyPure(fn('not-found')), 'err_not_found');
      expect(userErrorKeyPure(fn('invalid-argument')), 'err_invalid');
      expect(userErrorKeyPure(fn('internal')), 'err_server');
    });

    test('failed-precondition: umumiy yoki amalga xos matn', () {
      expect(userErrorKeyPure(fn('failed-precondition')), 'err_conflict');
      expect(
        userErrorKeyPure(fn('failed-precondition'),
            fallbackKey: 'local_change_failed'),
        'local_change_failed',
      );
    });

    test('server xabari (message) xaritasi, bo\'lmasa kod bo\'yicha', () {
      expect(
        userErrorKeyPure(
          fn('failed-precondition', 'insufficient_balance'),
          byServerMessage: const {'insufficient_balance': 'tv_ad_insufficient_balance'},
        ),
        'tv_ad_insufficient_balance',
      );
      // Dasturchi matni ('carpetCount 1..20') hech qachon ko'rsatilmaydi.
      expect(userErrorKeyPure(fn('invalid-argument', 'carpetCount 1..20')),
          'err_invalid');
    });

    test('noma\'lum kod -> fallback', () {
      expect(userErrorKeyPure(fn('some-new-code')), 'err_unexpected');
      expect(userErrorKeyPure(fn('some-new-code'), fallbackKey: 'x_failed'),
          'x_failed');
    });
  });

  group('userErrorKeyPure — boshqa xatolar', () {
    test('FirebaseException (firestore)', () {
      expect(
        userErrorKeyPure(
            FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied')),
        'err_permission',
      );
      expect(
        userErrorKeyPure(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable')),
        'err_network',
      );
    });

    test('Timeout / Socket', () {
      expect(userErrorKeyPure(TimeoutException('t')), 'err_timeout');
      expect(userErrorKeyPure(const SocketException('no route')), 'err_network');
    });

    test('oddiy Exception / StateError — xom matn chiqmaydi', () {
      expect(userErrorKeyPure(Exception('Қидирувда хатолик: boom')),
          'err_unexpected');
      expect(userErrorKeyPure(StateError('internal detail')), 'err_unexpected');
      expect(userErrorKeyPure(Exception('x'), fallbackKey: 'op_failed'),
          'op_failed');
    });
  });

  test('qaytishi mumkin bo\'lgan barcha err_* kalitlari 3 tilda mavjud', () {
    Map<String, dynamic> load(String l) =>
        jsonDecode(File('assets/lang/$l.json').readAsStringSync())
            as Map<String, dynamic>;
    const keys = [
      'err_retry',
      'err_network',
      'err_timeout',
      'err_too_many',
      'err_auth',
      'err_permission',
      'err_not_found',
      'err_server',
      'err_unexpected',
      'err_invalid',
      'err_conflict',
      'err_load_failed',
      'local_trip_load_failed',
      'local_trip_not_found',
    ];
    for (final l in ['uz_Cyrl', 'uz_Latn', 'ru']) {
      final m = load(l);
      for (final k in keys) {
        expect((m[k] as String?)?.trim().isNotEmpty, isTrue, reason: '$k / $l');
      }
    }
  });
}
