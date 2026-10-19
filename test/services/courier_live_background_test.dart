// Курьер фон кузатуви: рўйхат ва «тирик» қоидалари (соф функциялар).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ava_gurlan/services/courier_live_background.dart';

void main() {
  group('parse', () {
    test('тўғри қаторлар ўқилади, такрорий, бузилган ва бўш ташланади', () {
      final r = CourierLiveBackground.parse(['o1|c1', 'o1|c1', 'o2|c2', 'x', '|c', 'o|', '']);
      expect(r, const [
        CourierLiveEntry(orderId: 'o1', courierId: 'c1'),
        CourierLiveEntry(orderId: 'o2', courierId: 'c2'),
      ]);
    });

    test('null — бўш рўйхат', () {
      expect(CourierLiveBackground.parse(null), isEmpty);
    });
  });

  group('add / remove', () {
    test('қўшиш такрорлаш ҳосил қилмайди (идемпотент)', () {
      const e = CourierLiveEntry(orderId: 'o1', courierId: 'c1');
      final once = CourierLiveBackground.add(null, e);
      final twice = CourierLiveBackground.add(once, e);
      expect(twice, ['o1|c1']);
    });

    test('чиқариш фақат шу буюртмани олиб ташлайди', () {
      expect(CourierLiveBackground.remove(['o1|c1', 'o2|c2'], 'o1'), ['o2|c2']);
      expect(CourierLiveBackground.remove(['o1|c1'], 'yo\'q'), ['o1|c1']);
      expect(CourierLiveBackground.remove(null, 'o1'), isEmpty);
    });
  });

  group('isFresh', () {
    final now = DateTime.utc(2026, 10, 19, 12);
    test('90 с ичида — тирик; 91 с — йўқ; вақти йўқ — йўқ; келажак — йўқ', () {
      int ago(int s) => now.subtract(Duration(seconds: s)).millisecondsSinceEpoch;
      expect(CourierLiveBackground.isFresh(ago(89), now), isTrue);
      expect(CourierLiveBackground.isFresh(ago(90), now), isTrue);
      expect(CourierLiveBackground.isFresh(ago(91), now), isFalse);
      expect(CourierLiveBackground.isFresh(null, now), isFalse);
      expect(CourierLiveBackground.isFresh(now.add(const Duration(seconds: 5)).millisecondsSinceEpoch, now), isFalse);
    });
  });

  test('хизмат ёзмаган (heartbeat йўқ) бўлса илова ичидаги ёзувчи ишлайди', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await CourierLiveBackground.serviceCovers(), isFalse);
  });

  test('хизмат янги heartbeat ёзган бўлса илова ичидаги ёзувчи қўш ёзмайди', () async {
    final now = DateTime.utc(2026, 10, 19, 12);
    SharedPreferences.setMockInitialValues({CourierLiveBackground.heartbeatKey: now.subtract(const Duration(seconds: 30)).millisecondsSinceEpoch});
    expect(await CourierLiveBackground.serviceCovers(clock: () => now), isTrue);
    SharedPreferences.setMockInitialValues({CourierLiveBackground.heartbeatKey: now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch});
    expect(await CourierLiveBackground.serviceCovers(clock: () => now), isFalse);
  });
}