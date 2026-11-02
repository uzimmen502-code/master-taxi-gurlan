// Рағбат дастурлари админи: сервер хато кодлари → админ матни (эга 2026-11-02).
import 'package:ava_gurlan/features/admin_web/services/admin_incentives_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

FirebaseFunctionsException _err(String code) =>
    FirebaseFunctionsException(code: 'invalid-argument', message: code, details: {'code': code});

void main() {
  test('aniq kod: budgetTotal_below_granted umumiy budgetTotal bilan adashmaydi', () {
    expect(incentiveAdminError(_err('VALIDATION_budgetTotal_below_granted')),
        contains('аллақачон берилган'));
    expect(incentiveAdminError(_err('VALIDATION_budgetTotal')), contains('камида битта'));
  });

  test('buckets_sum va buckets alohida matn', () {
    expect(incentiveAdminError(_err('VALIDATION_buckets_sum')), contains('йиғиндиси'));
    expect(incentiveAdminError(_err('VALIDATION_buckets')), contains('такрорланмасин'));
  });

  test('ruxsat yo\'q va noma\'lum xato — stack trace emas, tushunarli matn', () {
    expect(
      incentiveAdminError(FirebaseFunctionsException(code: 'permission-denied', message: 'Admin only')),
      'Рухсат йўқ (фақат админ).',
    );
    expect(incentiveAdminError(StateError('boom')), 'Амал бажарилмади. Қайта уриниб кўринг.');
  });
}
