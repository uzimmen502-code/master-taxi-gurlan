import 'dart:async';

import 'package:ava_gurlan/features/ev_charging/controllers/ev_car_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

// Жонли машина: GPS оқими (сохта), йўналиш қоидаси, рухсат йўқ ҳолати.

class _Source implements EvCarLocationSource {
  _Source({this.denied = false, this.throwOnOpen = false});

  final bool denied;
  final bool throwOnOpen;
  final ctrl = StreamController<EvCarFix>.broadcast();
  int opens = 0;

  @override
  Future<Stream<EvCarFix>?> open() async {
    opens++;
    if (throwOnOpen) throw StateError('platform error');
    if (denied) return null;
    return ctrl.stream;
  }
}

EvCarFix _fix(double lat, double lng, {double? h, double? v}) =>
    EvCarFix(lat: lat, lng: lng, headingDeg: h, speedMps: v);

void main() {
  group('bearingDegrees', () {
    test('шимол 0, шарқ 90, жануб 180, ғарб 270', () {
      expect(EvCarTracker.bearingDegrees(41, 60, 42, 60), closeTo(0, 0.01));
      expect(EvCarTracker.bearingDegrees(41, 60, 41, 61), closeTo(90, 0.7));
      expect(EvCarTracker.bearingDegrees(41, 60, 40, 60), closeTo(180, 0.01));
      expect(EvCarTracker.bearingDegrees(41, 60, 41, 59), closeTo(270, 0.7));
    });
  });

  group('resolveHeading', () {
    test('ҳаракатда қурилма йўналиши ишлатилади', () {
      final h = EvCarTracker.resolveHeading(
        prevLat: 41,
        prevLng: 60,
        prevHeading: 10,
        next: _fix(41.001, 60, h: 123, v: 12),
      );
      expect(h, 123);
    });

    test('360 → 0', () {
      final h = EvCarTracker.resolveHeading(
        prevLat: null,
        prevLng: null,
        prevHeading: 0,
        next: _fix(41, 60, h: 360, v: 5),
      );
      expect(h, 0);
    });

    test('тўхтаганда (тезлик ~0) қурилма йўналиши ишонарсиз — олдингиси қолади',
        () {
      final h = EvCarTracker.resolveHeading(
        prevLat: 41,
        prevLng: 60,
        prevHeading: 77,
        next: _fix(41, 60, h: 0, v: 0),
      );
      expect(h, 77);
    });

    test('йўналиш йўқ, лекин сезиларли силжиган — икки нуқта азимути', () {
      // ~111 м шарққа.
      final h = EvCarTracker.resolveHeading(
        prevLat: 41,
        prevLng: 60,
        prevHeading: 0,
        next: _fix(41, 60.0013),
      );
      expect(h, closeTo(90, 1));
    });

    test('жуда кичик силжиш (GPS шовқини) — йўналиш ўзгармайди', () {
      final h = EvCarTracker.resolveHeading(
        prevLat: 41,
        prevLng: 60,
        prevHeading: 33,
        next: _fix(41.00002, 60.00002),
      );
      expect(h, 33);
    });

    test('яроқсиз қиймат (NaN, манфий) эътиборга олинмайди', () {
      for (final bad in [double.nan, -1.0, 400.0]) {
        final h = EvCarTracker.resolveHeading(
          prevLat: null,
          prevLng: null,
          prevHeading: 5,
          next: _fix(41, 60, h: bad, v: 20),
        );
        expect(h, 5, reason: '$bad');
      }
    });
  });

  group('EvCarTracker', () {
    test('нуқталар келади — fix ва йўналиш янгиланади', () async {
      final s = _Source();
      final t = EvCarTracker(source: s);
      var notified = 0;
      t.addListener(() => notified++);
      await t.start();
      expect(t.hasFix, isFalse);

      s.ctrl.add(_fix(41, 60, h: 30, v: 10));
      await Future<void>.delayed(Duration.zero);
      expect(t.hasFix, isTrue);
      expect(t.fix!.lat, 41);
      expect(t.heading, 30);
      expect(t.unavailable, isFalse);
      expect(notified, 1);
      t.dispose();
    });

    test('рухсат йўқ / GPS ўчиқ: маркер йўқ, хато йўқ, бир марта очилади',
        () async {
      final s = _Source(denied: true);
      final t = EvCarTracker(source: s);
      await t.start();
      await t.start(); // такрорий start — қайта сўров йўқ
      expect(t.hasFix, isFalse);
      expect(t.unavailable, isTrue);
      expect(s.opens, 1);
      t.dispose();
    });

    test('манба истисно ташласа — тинчгина "мавжуд эмас"', () async {
      final t = EvCarTracker(source: _Source(throwOnOpen: true));
      await t.start();
      expect(t.hasFix, isFalse);
      expect(t.unavailable, isTrue);
      t.dispose();
    });

    test('оқим хато берса — тўхтайди, қайта уриниш цикли йўқ', () async {
      final s = _Source();
      final t = EvCarTracker(source: s);
      await t.start();
      s.ctrl.add(_fix(41, 60));
      await Future<void>.delayed(Duration.zero);
      s.ctrl.addError(StateError('gps lost'));
      await Future<void>.delayed(Duration.zero);
      expect(t.unavailable, isTrue);
      expect(t.hasFix, isTrue, reason: 'охирги маълум нуқта қолади');
      expect(s.opens, 1);
      t.dispose();
    });

    test('pause оқимни ёпади, resume қайта очади (иловa фонга ўтса)', () async {
      final s = _Source();
      final t = EvCarTracker(source: s);
      await t.start();
      t.pause();
      s.ctrl.add(_fix(41, 60));
      await Future<void>.delayed(Duration.zero);
      expect(t.hasFix, isFalse, reason: 'пауза пайтида нуқта олинмайди');

      await t.resume();
      expect(s.opens, 2);
      s.ctrl.add(_fix(41.1, 60));
      await Future<void>.delayed(Duration.zero);
      expect(t.fix!.lat, 41.1);
      t.dispose();
    });

    test('dispose дан кейин нуқта келса — хато йўқ', () async {
      final s = _Source();
      final t = EvCarTracker(source: s);
      await t.start();
      t.dispose();
      s.ctrl.add(_fix(41, 60));
      await Future<void>.delayed(Duration.zero);
      expect(t.hasFix, isFalse);
    });
  });
}
