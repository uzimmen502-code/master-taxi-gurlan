import 'package:ava_gurlan/features/home/widgets/home_dating_section.dart';
import 'package:flutter_test/flutter_test.dart';

String _birthDateForAge(int age) {
  final now = DateTime.now();
  // Tug'ilgan kunni o'tgan qilib olamiz — yosh aniq `age` bo'lsin.
  final d = DateTime(now.year - age, 1, 1);
  return '${d.year}-01-01';
}

void main() {
  group('datingSectionVisibleFor — 18+ darvozasi', () {
    test('18 yosh — ko‘rinadi', () {
      expect(datingSectionVisibleFor(_birthDateForAge(18)), isTrue);
    });

    test('25 yosh — ko‘rinadi', () {
      expect(datingSectionVisibleFor(_birthDateForAge(25)), isTrue);
    });

    test('17 yosh — KO‘RINMAYDI', () {
      expect(datingSectionVisibleFor(_birthDateForAge(17)), isFalse);
    });

    test('bo‘sh tug‘ilgan sana — KO‘RINMAYDI', () {
      // Ega qarori: yoshi noma'lum foydalanuvchiga 18+ bo'lim
      // ko'rsatilmaydi.
      expect(datingSectionVisibleFor(''), isFalse);
      expect(datingSectionVisibleFor('   '), isFalse);
    });

    test('buzuq sana — KO‘RINMAYDI', () {
      expect(datingSectionVisibleFor('nomalum'), isFalse);
      expect(datingSectionVisibleFor('2026-13-45'), isFalse);
    });

    test('nuqtali format ham tushuniladi', () {
      final now = DateTime.now();
      expect(datingSectionVisibleFor('01.01.${now.year - 30}'), isTrue);
      expect(datingSectionVisibleFor('01.01.${now.year - 10}'), isFalse);
    });
  });

  group('datingInitial — rasm o‘rniga bosh harf', () {
    test('kirill ism', () {
      expect(datingInitial('Азиза'), 'А');
    });

    test('lotin ism', () {
      expect(datingInitial('aziza'), 'A');
    });

    test('bo‘shliq bilan boshlansa trim qilinadi', () {
      expect(datingInitial('  Дилноза'), 'Д');
    });

    test('bo‘sh ism — savol belgisi', () {
      expect(datingInitial(''), '?');
      expect(datingInitial('   '), '?');
    });

    test('emoji bilan boshlansa yiqilmaydi', () {
      expect(datingInitial('🌸Гул'), '🌸');
    });
  });
}
