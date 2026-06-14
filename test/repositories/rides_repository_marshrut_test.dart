import 'package:flutter_test/flutter_test.dart';
import 'package:master_taxi_gurlan/repositories/rides_repository.dart';

void main() {
  group('RidesRepository.normalizeMarshrutPhone', () {
    test('strips non-digits and keeps national number', () {
      expect(
        RidesRepository.normalizeMarshrutPhone('+998 90 123-45-67'),
        '998901234567',
      );
      expect(RidesRepository.normalizeMarshrutPhone('901234567'), '901234567');
    });

    test('trims whitespace', () {
      expect(
        RidesRepository.normalizeMarshrutPhone('  901234567  '),
        '901234567',
      );
    });
  });
}
