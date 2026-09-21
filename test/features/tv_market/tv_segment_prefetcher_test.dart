import 'package:ava_gurlan/features/tv_market/services/tv_segment_prefetcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final calls = <(String, Map<String, dynamic>)>[];

  setUp(() {
    calls.clear();
    TvSegmentPrefetcher.invokeOverride = (m, a) async => calls.add((m, a));
  });

  tearDown(() => TvSegmentPrefetcher.invokeOverride = null);

  group('secondsFor — tarmoq jadvali', () {
    test('Wi-Fi (720p): NEXT 3s (1 segment), NEXT+1 faqat playlist (0)', () {
      expect(TvSegmentPrefetcher.secondsFor('720p', nextPlusOne: false), 3);
      expect(TvSegmentPrefetcher.secondsFor('720p', nextPlusOne: true), 0);
    });
    test('mobil (480p): NEXT 2s (1 segment), NEXT+1 faqat playlist (0)', () {
      expect(TvSegmentPrefetcher.secondsFor('480p', nextPlusOne: false), 2);
      expect(TvSegmentPrefetcher.secondsFor('480p', nextPlusOne: true), 0);
    });
    test('mobil + sekin tarix: NEXT 2s, NEXT+1 yo\'q', () {
      expect(
          TvSegmentPrefetcher.secondsFor('480p',
              nextPlusOne: false, slowHistory: true),
          2);
      expect(
          TvSegmentPrefetcher.secondsFor('480p',
              nextPlusOne: true, slowHistory: true),
          isNull);
    });
    test('noma\'lum/yo\'q (360p): NEXT 2s, NEXT+1 yo\'q', () {
      expect(TvSegmentPrefetcher.secondsFor('360p', nextPlusOne: false), 2);
      expect(TvSegmentPrefetcher.secondsFor('360p', nextPlusOne: true), isNull);
    });
  });

  group('prefetch', () {
    test('HLS bo\'lmagan (mp4) URL — no-op (TvClipCacheService qoladi)', () async {
      await TvSegmentPrefetcher.prefetch('https://x/a.mp4', seconds: 3);
      expect(calls, isEmpty);
    });
    test('bo\'sh URL — no-op', () async {
      await TvSegmentPrefetcher.prefetch('', seconds: 3);
      expect(calls, isEmpty);
    });
    test('HLS — prefetch(url, seconds) native\'ga uzatiladi', () async {
      await TvSegmentPrefetcher.prefetch('https://x/c/master.m3u8', seconds: 3);
      expect(calls.single.$1, 'prefetch');
      expect(calls.single.$2, {'url': 'https://x/c/master.m3u8', 'seconds': 3});
    });
    test('markWanted → prefetch tartibi (svayp); mp4 ro\'yxatdan chiqariladi',
        () async {
      await TvSegmentPrefetcher.markWanted(
          ['https://x/c/master.m3u8', 'https://x/old.mp4', '']);
      await TvSegmentPrefetcher.prefetch('https://x/n/master.m3u8', seconds: 3);
      expect(calls.map((c) => c.$1).toList(), ['markWanted', 'prefetch']);
      expect(calls.first.$2['urls'], ['https://x/c/master.m3u8']);
    });
  });
}
