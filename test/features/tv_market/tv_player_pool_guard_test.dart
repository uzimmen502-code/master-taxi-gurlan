import 'package:ava_gurlan/features/tv_market/services/tv_player_pool.dart';
import 'package:flutter_test/flutter_test.dart';

/// В-4 0-босқич: `processingStatus` ва `canStartPlayback` ажратилгандан
/// кейин, `TvPlayerPool` даражасидаги мажбурий гуардни текширади — UI
/// қатлами хато қилса (масалан янги экран `canStartPlayback`ни текшир-
/// масдан URL узатса) ҳам, ХОМ/тайёр бўлмаган видео ҳеч қачон ўйнатил-
/// маслигини тасдиқлайди.
void main() {
  group('TvPlayerPool.prepare — isReady гуарди', () {
    test(
        'isReady: false бўлса — controller ҳеч қачон яратилмайди '
        '(URL ҳақиқий бўлса ҳам)', () async {
      final ctrl = await TvPlayerPool.shared.prepare(
        'https://example.com/still-processing.mp4',
        isReady: false,
      );
      expect(ctrl, isNull);
    });

    test(
        'isReady узатилмаса (default true) — эскирган чақирувлар '
        'ўзгармайди: бўш url барибир null қайтаради', () async {
      final ctrl = await TvPlayerPool.shared.prepare('');
      expect(ctrl, isNull);
    });
  });

  group('TvPlayerPool.retain — isReady харитаси', () {
    test(
        'isReady харитасида false деб белгиланган url тайёр ('
        'ready) рўйхатга ҳеч қачон қўшилмайди', () async {
      const url = 'https://example.com/not-ready-retain.mp4';
      await TvPlayerPool.shared.retain([url], isReady: {url: false});
      expect(TvPlayerPool.shared[url], isNull);
    });
  });
}
