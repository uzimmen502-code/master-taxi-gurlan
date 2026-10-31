import 'package:ava_gurlan/features/yuk_local/yuk_local_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _at(int hour, [int minute = 0]) => DateTime(2026, 9, 15, hour, minute);

void main() {
  group('YukLocalSchedule.isWithinWorkHours', () {
    bool within(int start, int end, DateTime now) =>
        YukLocalSchedule.isWithinWorkHours(
          workStartMinutes: start,
          workEndMinutes: end,
          now: now,
        );

    test('00:00–24:00 — бут кун', () {
      expect(within(0, 24 * 60, _at(0)), isTrue);
      expect(within(0, 24 * 60, _at(23, 59)), isTrue);
    });

    test('start == end — бут кун деб қабул қилинади', () {
      expect(within(9 * 60, 9 * 60, _at(3)), isTrue);
    });

    test('кундузги смена 09:00–18:00: бошланиш inclusive, тугаш exclusive', () {
      expect(within(9 * 60, 18 * 60, _at(8, 59)), isFalse);
      expect(within(9 * 60, 18 * 60, _at(9, 0)), isTrue);
      expect(within(9 * 60, 18 * 60, _at(17, 59)), isTrue);
      expect(within(9 * 60, 18 * 60, _at(18, 0)), isFalse);
    });

    test('кечага ўтувчи смена 22:00–06:00', () {
      expect(within(22 * 60, 6 * 60, _at(23)), isTrue);
      expect(within(22 * 60, 6 * 60, _at(2)), isTrue);
      expect(within(22 * 60, 6 * 60, _at(5, 59)), isTrue);
      expect(within(22 * 60, 6 * 60, _at(6, 0)), isFalse);
      expect(within(22 * 60, 6 * 60, _at(12)), isFalse);
      expect(within(22 * 60, 6 * 60, _at(21, 59)), isFalse);
    });

    test('чегарадан чиққан қийматлар clamp қилинади', () {
      expect(within(-100, 30 * 60, _at(12)), isTrue);
    });
  });

  group('YukLocalSchedule — дақиқа утилиталари', () {
    test('clampMinutes 0…1440', () {
      expect(YukLocalSchedule.clampMinutes(-5), 0);
      expect(YukLocalSchedule.clampMinutes(1500), 1440);
      expect(YukLocalSchedule.clampMinutes(600), 600);
    });

    test('formatMinutes', () {
      expect(YukLocalSchedule.formatMinutes(0), '00:00');
      expect(YukLocalSchedule.formatMinutes(9 * 60 + 5), '09:05');
      expect(YukLocalSchedule.formatMinutes(24 * 60), '24:00');
    });

    test('splitMinutes: 24:00 → (23, 59)', () {
      expect(YukLocalSchedule.splitMinutes(24 * 60), (23, 59));
      expect(YukLocalSchedule.splitMinutes(13 * 60 + 30), (13, 30));
    });

    test('timeOfDayToMinutes', () {
      expect(YukLocalSchedule.timeOfDayToMinutes(8, 15), 495);
    });

    test('TTL: биринчи эълон 60 кун, кейингилари 30 кун (эга 2026-10-31)', () {
      expect(YukLocalSchedule.firstListingTtl, const Duration(days: 60));
      expect(YukLocalSchedule.nextListingTtl, const Duration(days: 30));
    });
  });

  group('YukLocalSchedule.canRenew (эга 2026-10-31: ≤3 кун ёки ўтган, 30 кун ичида)', () {
    final now = DateTime(2026, 11, 1, 10);
    bool can(Duration left) =>
        YukLocalSchedule.canRenew(now.add(left), now: now);

    test('муддат йўқ — йўқ', () {
      expect(YukLocalSchedule.canRenew(null, now: now), isFalse);
    });
    test('4 кун қолган — ҳали эрта', () {
      expect(can(const Duration(days: 4)), isFalse);
    });
    test('чегара: роппа-роса 3 кун — мумкин; 3 кун + 1 дақиқа — йўқ', () {
      expect(can(const Duration(days: 3)), isTrue);
      expect(can(const Duration(days: 3, minutes: 1)), isFalse);
    });
    test('1 соат қолган ва 5 кун олдин ўтган — мумкин', () {
      expect(can(const Duration(hours: 1)), isTrue);
      expect(can(const Duration(days: -5)), isTrue);
    });
    test('30 кундан кўп олдин ўтган (сервер ўчиради) — йўқ', () {
      expect(can(const Duration(days: -30)), isTrue);
      expect(can(const Duration(days: -30, minutes: -1)), isFalse);
    });
  });
}
