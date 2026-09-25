import 'package:ava_gurlan/features/home/widgets/home_intercity_section.dart';
import 'package:ava_gurlan/models/intercity_ride.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

IntercityRide _ride({int male = 0, int female = 0}) => IntercityRide(
      id: 'r1',
      driverName: 'Ali',
      rating: 4.5,
      carModel: 'Cobalt',
      carNumber: '95 A 123 BC',
      phoneNumber: '998901234567',
      price: 50000,
      availableSeats: 2,
      fromCity: 'Gurlan',
      toCity: 'Urganch',
      district: 'gurlan',
      departureTime: DateTime(2026, 1, 1, 8),
      maleCount: male,
      femaleCount: female,
    );

/// Kontekst talab qiladigan yordamchilarni chaqirish uchun.
Future<T> _withContext<T>(
  WidgetTester tester,
  T Function(BuildContext c) fn,
) async {
  late T out;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          out = fn(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return out;
}

void main() {
  group('formatDepartureLabel', () {
    testWidgets('bugungi reys — "Bugun HH:mm"', (tester) async {
      final now = DateTime.now();
      final at = DateTime(now.year, now.month, now.day, 14, 30);
      final s = await _withContext(tester, (c) => formatDepartureLabel(c, at));
      expect(s, 'home_today 14:30');
    });

    testWidgets('ertangi reys — "Ertaga HH:mm"', (tester) async {
      final at = DateTime.now().add(const Duration(days: 1));
      final d = DateTime(at.year, at.month, at.day, 7);
      final s = await _withContext(tester, (c) => formatDepartureLabel(c, d));
      expect(s, 'home_tomorrow 07:00');
    });

    testWidgets('uzoqroq kun — sana bilan', (tester) async {
      final at = DateTime.now().add(const Duration(days: 5));
      final d = DateTime(at.year, at.month, at.day, 9, 5);
      final s = await _withContext(tester, (c) => formatDepartureLabel(c, d));
      final dd = d.day.toString().padLeft(2, '0');
      final mm = d.month.toString().padLeft(2, '0');
      expect(s, '$dd.$mm 09:05');
    });
  });

  group('formatCabinLabel — yo‘lovchi maxfiyligi', () {
    testWidgets('faqat ayol', (tester) async {
      final s = await _withContext(
        tester,
        (c) => formatCabinLabel(c, _ride(female: 1)),
      );
      expect(s, 'home_intercity_cabin: 1 home_gender_female');
    });

    testWidgets('erkak va ayol — vergul bilan', (tester) async {
      final s = await _withContext(
        tester,
        (c) => formatCabinLabel(c, _ride(male: 2, female: 1)),
      );
      expect(s, 'home_intercity_cabin: 2 home_gender_male, 1 home_gender_female');
    });

    testWidgets('salon bo‘sh — matn umuman yo‘q', (tester) async {
      final s = await _withContext(tester, (c) => formatCabinLabel(c, _ride()));
      expect(s, '');
    });

    testWidgets('isim va telefon yorliqqa TUSHMAYDI', (tester) async {
      // Tavsif talabi: yo'lovchilarning ismi va rasmi ko'rsatilmaydi.
      // Haydovchining ismi/telefoni ham bu qatorda bo'lmasligi kerak.
      final s = await _withContext(
        tester,
        (c) => formatCabinLabel(c, _ride(male: 1)),
      );
      expect(s.contains('Ali'), isFalse);
      expect(s.contains('998901234567'), isFalse);
    });
  });

  group('IntercityRide — mashina ko‘rinishi', () {
    test('model va raqam birga', () {
      expect(_ride().carDisplay, 'Cobalt · 95 A 123 BC');
    });
  });
}
