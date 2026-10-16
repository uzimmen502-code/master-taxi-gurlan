import 'package:ava_gurlan/utils/intercity_departure.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

/// Haydovchi jo'nash vaqti: standart tanlov va o'tib ketgan vaqtni to'sish.
/// Soat parametr sifatida beriladi — real vaqtga bog'liq emas.
void main() {
  const eight = TimeOfDay(hour: 8, minute: 0);

  group('smartDefault', () {
    test('real telefonda kuzatilgan holat: 15:02 da 08:00 bugun → 15:30', () {
      final r = IntercityDeparture.smartDefault(
        now: DateTime(2026, 10, 16, 15, 2),
        preferred: eight,
        preferredTomorrow: false,
      );
      expect(r.tomorrow, isFalse);
      expect(r.time, const TimeOfDay(hour: 15, minute: 30));
    });

    test('kelajakdagi vaqt (>= 10 daqiqa) o\'zgarmaydi', () {
      final r = IntercityDeparture.smartDefault(
        now: DateTime(2026, 10, 16, 7, 0),
        preferred: eight,
        preferredTomorrow: false,
      );
      expect(r.time, eight);
      expect(r.tomorrow, isFalse);
    });

    test('chegara: aynan 10 daqiqa oldinda — o\'zgarmaydi; 9 daqiqa — yangilanadi', () {
      final keep = IntercityDeparture.smartDefault(
        now: DateTime(2026, 10, 16, 7, 50),
        preferred: eight,
        preferredTomorrow: false,
      );
      expect(keep.time, eight);
      final shift = IntercityDeparture.smartDefault(
        now: DateTime(2026, 10, 16, 7, 51),
        preferred: eight,
        preferredTomorrow: false,
      );
      expect(shift.time, const TimeOfDay(hour: 8, minute: 30));
      expect(shift.tomorrow, isFalse);
    });

    test('"Ertaga" tanlovi doim saqlanadi (vaqt ham)', () {
      final r = IntercityDeparture.smartDefault(
        now: DateTime(2026, 10, 16, 23, 50),
        preferred: eight,
        preferredTomorrow: true,
      );
      expect(r.tomorrow, isTrue);
      expect(r.time, eight);
    });

    test('23:30 dan keyin → ertaga 08:00', () {
      for (final now in [
        DateTime(2026, 10, 16, 23, 30),
        DateTime(2026, 10, 16, 23, 45),
        DateTime(2026, 10, 16, 23, 59),
        // 23:25 → 23:30 slot 10 daqiqadan kam → keyingisi yarim tun
        DateTime(2026, 10, 16, 23, 25),
      ]) {
        final r = IntercityDeparture.smartDefault(
            now: now, preferred: eight, preferredTomorrow: false);
        expect(r.tomorrow, isTrue, reason: '$now');
        expect(r.time, eight, reason: '$now');
      }
    });

    test('23:05 → bugun 23:30 (hali bugunga sig\'adi)', () {
      final r = IntercityDeparture.smartDefault(
        now: DateTime(2026, 10, 16, 23, 5),
        preferred: eight,
        preferredTomorrow: false,
      );
      expect(r.tomorrow, isFalse);
      expect(r.time, const TimeOfDay(hour: 23, minute: 30));
    });

    test('oy oxiri: 31-kun 23:40 → ertaga (oy almashuvi)', () {
      final r = IntercityDeparture.smartDefault(
        now: DateTime(2026, 10, 31, 23, 40),
        preferred: eight,
        preferredTomorrow: false,
      );
      expect(r.tomorrow, isTrue);
    });
  });

  group('nextSlot', () {
    test(':00 / :30 chegaralari', () {
      TimeOfDay slot(int h, int m) =>
          IntercityDeparture.nextSlot(DateTime(2026, 10, 16, h, m)).time;
      expect(slot(10, 0), const TimeOfDay(hour: 10, minute: 30));
      expect(slot(10, 19), const TimeOfDay(hour: 10, minute: 30));
      expect(slot(10, 20), const TimeOfDay(hour: 10, minute: 30));
      expect(slot(10, 21), const TimeOfDay(hour: 11, minute: 0));
      expect(slot(10, 29), const TimeOfDay(hour: 11, minute: 0));
      expect(slot(10, 30), const TimeOfDay(hour: 11, minute: 0));
      expect(slot(10, 50), const TimeOfDay(hour: 11, minute: 0));
      expect(slot(10, 51), const TimeOfDay(hour: 11, minute: 30));
    });
  });

  group('isInPast', () {
    final now = DateTime(2026, 10, 16, 15, 2);

    test('bugun + o\'tgan vaqt → to\'siladi', () {
      expect(
        IntercityDeparture.isInPast(
            now: now, tomorrow: false, time: eight),
        isTrue,
      );
    });

    test('bugun + kelajak → ruxsat', () {
      expect(
        IntercityDeparture.isInPast(
            now: now,
            tomorrow: false,
            time: const TimeOfDay(hour: 15, minute: 30)),
        isFalse,
      );
    });

    test('ertaga har doim ruxsat (08:00 ham)', () {
      expect(
        IntercityDeparture.isInPast(now: now, tomorrow: true, time: eight),
        isFalse,
      );
    });

    test('chegara: 2 daqiqa muhlat — 15:00 ruxsat, 14:59 to\'siladi', () {
      expect(
        IntercityDeparture.isInPast(
            now: now,
            tomorrow: false,
            time: const TimeOfDay(hour: 15, minute: 0)),
        isFalse,
      );
      expect(
        IntercityDeparture.isInPast(
            now: now,
            tomorrow: false,
            time: const TimeOfDay(hour: 14, minute: 59)),
        isTrue,
      );
    });

    test('kun oxiri: 23:59 da bugun 23:00 to\'siladi, ertaga 00:30 ruxsat', () {
      final late = DateTime(2026, 10, 16, 23, 59);
      expect(
        IntercityDeparture.isInPast(
            now: late,
            tomorrow: false,
            time: const TimeOfDay(hour: 23, minute: 0)),
        isTrue,
      );
      expect(
        IntercityDeparture.isInPast(
            now: late,
            tomorrow: true,
            time: const TimeOfDay(hour: 0, minute: 30)),
        isFalse,
      );
    });
  });

  group('reschedule dialogi', () {
    final now = DateTime(2026, 10, 16, 15, 2);

    test('bugun tanlansa boshlang\'ich vaqt o\'tmishda emas', () {
      final t = IntercityDeparture.initialRescheduleTime(
          now: now, pickedDay: DateTime(2026, 10, 16));
      expect(t, const TimeOfDay(hour: 15, minute: 30));
    });

    test('boshqa kun → 08:00', () {
      expect(
        IntercityDeparture.initialRescheduleTime(
            now: now, pickedDay: DateTime(2026, 10, 17)),
        eight,
      );
    });

    test('bugun kech (23:40) → boshlang\'ich 08:00 (bugun uchun slot yo\'q)', () {
      final t = IntercityDeparture.initialRescheduleTime(
          now: DateTime(2026, 10, 16, 23, 40),
          pickedDay: DateTime(2026, 10, 16));
      expect(t, eight);
      // ...lekin shu vaqt bugun uchun baribir to'siladi.
      expect(
        IntercityDeparture.isRescheduleInPast(
            now: DateTime(2026, 10, 16, 23, 40),
            pickedDay: DateTime(2026, 10, 16),
            time: t),
        isTrue,
      );
    });

    test('isRescheduleInPast: bugun o\'tgan → true; ertangi 08:00 → false', () {
      expect(
        IntercityDeparture.isRescheduleInPast(
            now: now, pickedDay: DateTime(2026, 10, 16), time: eight),
        isTrue,
      );
      expect(
        IntercityDeparture.isRescheduleInPast(
            now: now, pickedDay: DateTime(2026, 10, 17), time: eight),
        isFalse,
      );
    });
  });
}
