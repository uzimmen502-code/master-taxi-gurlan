import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_nav_relay.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_selection.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:flutter_test/flutter_test.dart';

// Toza mantiq: Google Maps chegarasidan ko'p to'xtash bo'laklab yuboriladi
// (evNavigationChunk) va keyingi bo'lak qachon taklif qilinishi (relay).

EvTripCandidate _c(String id, double along, {double? lat}) => EvTripCandidate(
      station: EvChargingStation(
        id: id,
        latitude: lat ?? 40 + along / 1000,
        longitude: 60,
        geohash: '',
        chargingTypes: const ['DC'],
        connectors: const ['CCS2'],
        status: 'working',
        verificationStatus: 'verified',
        confirmationCount: 1,
        reportCount: 0,
        createdBy: 'u',
        isActive: true,
      ),
      alongKm: along,
      offRouteKm: 0,
      kind: EvTripMarkerKind.other,
    );

List<EvTripCandidate> _many(int n) =>
    [for (var i = 0; i < n; i++) _c('s$i', 10.0 * (i + 1))];

List<String> _ids(List<EvTripCandidate> l) => [for (final c in l) c.id];

void main() {
  group('evNavigationChunk', () {
    test('bo\'sh ro\'yxat: ikkalasi ham bo\'sh', () {
      final r = evNavigationChunk<int>(const [], 3);
      expect(r.sent, isEmpty);
      expect(r.remaining, isEmpty);
    });

    test('chegaradan kam yoki teng: hammasi yuboriladi, qolgani yo\'q', () {
      for (final n in [1, 2, 3]) {
        final r = evNavigationChunk(List.generate(n, (i) => i), 3);
        expect(r.sent, List.generate(n, (i) => i), reason: 'n=$n');
        expect(r.remaining, isEmpty, reason: 'n=$n');
      }
      final r9 = evNavigationChunk(List.generate(9, (i) => i), 9);
      expect(r9.sent, hasLength(9));
      expect(r9.remaining, isEmpty);
    });

    test('chegaradan ko\'p (limit 3): birinchi 3 ta, qolgani qoladi, tartib '
        'saqlanadi', () {
      final r = evNavigationChunk([1, 2, 3, 4, 5, 6, 7], 3);
      expect(r.sent, [1, 2, 3]);
      expect(r.remaining, [4, 5, 6, 7]);
      final r4 = evNavigationChunk([1, 2, 3, 4], 3);
      expect(r4.sent, [1, 2, 3]);
      expect(r4.remaining, [4]);
    });

    test('chegaradan ko\'p (limit 9): birinchi 9 ta', () {
      final all = List.generate(10, (i) => i);
      final r = evNavigationChunk(all, 9);
      expect(r.sent, all.sublist(0, 9));
      expect(r.remaining, [9]);
    });

    test('takror "davom etish" bo\'laklari: limit 3 -> 3,3,1', () {
      final sizes = <int>[];
      var rest = List.generate(7, (i) => i);
      while (rest.isNotEmpty) {
        final r = evNavigationChunk(rest, 3);
        sizes.add(r.sent.length);
        rest = r.remaining;
      }
      expect(sizes, [3, 3, 1]);
    });

    test('takror "davom etish" bo\'laklari: limit 9 -> 9,9,2', () {
      final sizes = <int>[];
      var rest = List.generate(20, (i) => i);
      while (rest.isNotEmpty) {
        final r = evNavigationChunk(rest, 9);
        sizes.add(r.sent.length);
        rest = r.remaining;
      }
      expect(sizes, [9, 9, 2]);
    });

    test('limit < 1 ham cheksiz tsikl bermaydi (kamida 1)', () {
      final r = evNavigationChunk([1, 2, 3], 0);
      expect(r.sent, [1]);
      expect(r.remaining, [2, 3]);
      expect(evNavigationChunk([1, 2], -5).sent, [1]);
    });

    test('kirish ro\'yxatini o\'zgartirmaydi', () {
      final input = [1, 2, 3, 4];
      final r = evNavigationChunk(input, 2);
      r.sent.add(99);
      r.remaining.clear();
      expect(input, [1, 2, 3, 4]);
    });
  });

  group('EvNavigationRelay', () {
    test('boshida faol emas: pending bo\'sh, "o\'tdi" yo\'q', () {
      final r = EvNavigationRelay();
      expect(r.active, isFalse);
      expect(r.pending(_many(5)), isEmpty);
      expect(r.hasPassedLastSent(500), isFalse);
    });

    test('markSent: oxirgi yuborilgan masofa, pending - yuborilmaganlar', () {
      final all = _many(7); // 10..70 km
      final r = EvNavigationRelay();
      final chunk = evNavigationChunk(all, 3);
      r.markSent(chunk.sent);
      expect(r.active, isTrue);
      expect(r.lastSentAlongKm, 30);
      expect(_ids(r.pending(all)), ['s3', 's4', 's5', 's6']);
    });

    test('"o\'tdi" chegarasi: oxirgi yuborilgandan +1.5 km (teng ham)', () {
      final r = EvNavigationRelay();
      r.markSent([_c('a', 100)]);
      expect(EvNavigationRelay.passedMarginKm, 1.5);
      expect(r.hasPassedLastSent(99), isFalse);
      expect(r.hasPassedLastSent(100), isFalse);
      expect(r.hasPassedLastSent(101.49), isFalse);
      expect(r.hasPassedLastSent(101.5), isTrue);
      expect(r.hasPassedLastSent(300), isTrue);
    });

    test('mashina o\'rni noma\'lum (GPS yo\'q / yo\'lda emas) - o\'tmagan',
        () {
      final r = EvNavigationRelay();
      r.markSent([_c('a', 100)]);
      expect(r.hasPassedLastSent(null), isFalse);
    });

    test('keyingi bo\'lak yuborilgach chegara yangi oxirgi to\'xtashdan', () {
      final all = _many(7);
      final r = EvNavigationRelay();
      r.markSent(evNavigationChunk(all, 3).sent); // 10,20,30
      expect(r.hasPassedLastSent(31.6), isTrue);
      r.markSent(evNavigationChunk(r.pending(all), 3).sent); // 40,50,60
      expect(r.lastSentAlongKm, 60);
      expect(r.hasPassedLastSent(31.6), isFalse);
      expect(r.hasPassedLastSent(61.5), isTrue);
      expect(_ids(r.pending(all)), ['s6']);
    });

    test('to\'liq sikl: limit 3, 7 ta - 3+3+1, hech biri takrorlanmaydi',
        () {
      final all = _many(7);
      final r = EvNavigationRelay();
      final sentIds = <String>[];
      var chunk = evNavigationChunk(all, 3);
      sentIds.addAll(_ids(chunk.sent));
      r.markSent(chunk.sent);
      var guard = 0;
      while (r.pending(all).isNotEmpty && guard++ < 10) {
        chunk = evNavigationChunk(r.pending(all), 3);
        sentIds.addAll(_ids(chunk.sent));
        r.markSent(chunk.sent);
      }
      expect(sentIds, [for (final c in all) c.id]);
      expect(r.pending(all), isEmpty);
    });

    test('haydovchi olib tashlagan stansiya pending dan chiqadi', () {
      final all = _many(6);
      final r = EvNavigationRelay();
      r.markSent(evNavigationChunk(all, 3).sent);
      final withoutS4 = [for (final c in all) if (c.id != 's4') c];
      expect(_ids(r.pending(withoutS4)), ['s3', 's5']);
    });

    test('keyin qo\'shilgan: oxirgi yuborilgandan keyingisi pending ga '
        'kiradi, ortida qolgani esa yo\'q', () {
      final all = _many(4); // 10,20,30,40
      final r = EvNavigationRelay();
      r.markSent(evNavigationChunk(all, 3).sent); // 10,20,30
      final extraAhead = _c('new-ahead', 55);
      final extraBehind = _c('new-behind', 15);
      final withExtra = [all[0], extraBehind, ...all.sublist(1), extraAhead];
      expect(_ids(r.pending(withExtra)), ['s3', 'new-ahead']);
    });

    test('bir xil koordinatali boshqa id: allaqachon yuborilgan deb sanaladi',
        () {
      final r = EvNavigationRelay();
      r.markSent([_c('a', 100, lat: 41.0)]);
      final twin = _c('a-twin', 100, lat: 41.0);
      final other = _c('b', 110, lat: 41.1);
      expect(_ids(r.pending([twin, other])), ['b']);
    });

    test('reset: hammasi boshiga qaytadi', () {
      final r = EvNavigationRelay();
      r.markSent([_c('a', 100)]);
      r.reset();
      expect(r.active, isFalse);
      expect(r.lastSentAlongKm, isNull);
      expect(r.pending([_c('b', 200)]), isEmpty);
      expect(r.hasPassedLastSent(999), isFalse);
    });
  });
}
