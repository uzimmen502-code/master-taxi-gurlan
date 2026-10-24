import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/core/utils/firebase_functions_errors.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

/// Onboarding callable xatolari: server matni (lotincha) emas, kod bo'yicha
/// 3 tilli kalit.
void main() {
  FirebaseFunctionsException fn(String code, [String message = 'x']) =>
      FirebaseFunctionsException(code: code, message: message);

  test('tasdiq kodi / qurilma oqimiga xos kodlar', () {
    expect(onboardingErrorKey(fn('not-found')), 'ob_err_code_request_not_found');
    expect(onboardingErrorKey(fn('permission-denied')), 'ob_err_code_wrong');
    expect(onboardingErrorKey(fn('failed-precondition')), 'ob_err_device_mismatch');
  });

  test('umumiy kodlar userErrorKey bilan bir xil', () {
    expect(onboardingErrorKey(fn('unavailable')), 'err_network');
    expect(onboardingErrorKey(fn('deadline-exceeded')), 'err_timeout');
    expect(onboardingErrorKey(fn('resource-exhausted')), 'err_too_many');
    expect(onboardingErrorKey(fn('internal')), 'err_server');
    expect(onboardingErrorKey(fn('???')), 'err_unexpected');
  });

  test('server xabari (lotincha) hech qachon natijaga kirmaydi', () {
    final k = onboardingErrorKey(
        fn('failed-precondition', 'Qurilma vaqtincha cheklangan'));
    expect(k, isNot(contains('Qurilma')));
    expect(k, startsWith('ob_'));
  });

  test('qaytadigan barcha kalitlar 3 tilda mavjud', () {
    const keys = [
      'ob_err_code_request_not_found',
      'ob_err_code_wrong',
      'ob_err_device_mismatch',
    ];
    for (final l in ['uz_Cyrl', 'uz_Latn', 'ru']) {
      final m = jsonDecode(File('assets/lang/$l.json').readAsStringSync())
          as Map<String, dynamic>;
      for (final k in keys) {
        expect((m[k] as String?)?.trim().isNotEmpty, isTrue, reason: '$k/$l');
      }
    }
  });
}
