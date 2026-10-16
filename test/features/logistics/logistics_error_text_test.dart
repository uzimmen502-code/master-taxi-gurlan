// AVA LOGISTICS — сервер `details.reason` → матн калити ва 3 тилдаги матнлар.
//
//   flutter test test/features/logistics/logistics_error_text_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/features/logistics/data/logistics_repository.dart';
import 'package:ava_gurlan/features/logistics/ui/logistics_text.dart';

LogisticsException _err(String code, String reason) =>
    LogisticsException(code, reason, 'msg');

void main() {
  group('logisticsErrorKey', () {
    test('oddiy reason — logistics_err_<reason>', () {
      expect(logisticsErrorKey(_err('invalid-argument', 'declared_value_required')),
          'logistics_err_declared_value_required');
      expect(logisticsErrorKey(_err('invalid-argument', 'photo_url_invalid')),
          'logistics_err_photo_url_invalid');
      expect(logisticsErrorKey(_err('failed-precondition', 'declared_value_missing')),
          'logistics_err_declared_value_missing');
    });

    test('CODE_ATTEMPTS_LOCKED (resource-exhausted) — alohida kalit', () {
      expect(logisticsErrorKey(_err('resource-exhausted', 'CODE_ATTEMPTS_LOCKED')),
          'logistics_code_locked');
      // reason kelmasa repository reason = code qo'yadi
      expect(logisticsErrorKey(_err('resource-exhausted', 'resource-exhausted')),
          'logistics_code_locked');
    });

    test('LogisticsException bo\'lmagan xato — kalit yo\'q (umumiy matn)', () {
      expect(logisticsErrorKey(StateError('x')), isNull);
    });
  });

  group('3 tilda matn bor', () {
    const langs = ['uz_Cyrl', 'uz_Latn', 'ru'];
    const keys = [
      'logistics_err_declared_value_required',
      'logistics_err_declared_value_missing',
      'logistics_err_photo_url_invalid',
      'logistics_code_locked',
      'logistics_payment_loss_pending',
      'logistics_payment_loss_settled',
    ];

    for (final lang in langs) {
      test(lang, () {
        final m = json.decode(File('assets/lang/$lang.json').readAsStringSync())
            as Map<String, dynamic>;
        for (final k in keys) {
          expect((m[k] ?? '').toString().trim(), isNotEmpty, reason: '$lang: $k');
        }
        // 45-банд: мижоз матнида ички терминлар йўқ
        final customer = [
          m['logistics_payment_loss_pending'],
          m['logistics_payment_loss_settled'],
        ].join(' ').toLowerCase();
        for (final bad in ['leg', 'escrow', 'settlement', 'zone']) {
          expect(customer.contains(bad), isFalse, reason: '$lang: $bad');
        }
      });
    }
  });
}
