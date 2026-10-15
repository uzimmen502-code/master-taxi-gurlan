import 'package:ava_gurlan/repositories/taxi_billing_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _base() => {
      'allowed': true,
      'reason': 'ok',
      'feeAmount': 0,
      'quotedFee': 28000,
      'billable': false,
      'taxiStatus': 'starter',
    };

void main() {
  test('starterNotice: сервер true деса — true', () {
    final q = TaxiFeeQuote.fromMap({..._base(), 'starterNotice': true});
    expect(q.starterNotice, isTrue);
  });

  test('starterNotice: false ёки йўқ бўлса — false (диалог кўрсатилмайди)', () {
    expect(TaxiFeeQuote.fromMap({..._base(), 'starterNotice': false}).starterNotice,
        isFalse);
    expect(TaxiFeeQuote.fromMap(_base()).starterNotice, isFalse);
  });

  test('starterNotice: true дан бошқа қиймат (сатр, сон) — false', () {
    expect(TaxiFeeQuote.fromMap({..._base(), 'starterNotice': 'true'}).starterNotice,
        isFalse);
    expect(TaxiFeeQuote.fromMap({..._base(), 'starterNotice': 1}).starterNotice,
        isFalse);
  });
}
