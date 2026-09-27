import 'package:ava_gurlan/features/tv_market/services/tv_clip_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_compress/video_compress.dart';

void main() {
  test('кичик 720p сиқилмайди', () {
    expect(
      TvClipCompress.shouldSkip(height: 720, bytes: 2 * 1024 * 1024),
      isTrue,
    );
  });

  test('1080p сиқилади', () {
    expect(
      TvClipCompress.shouldSkip(height: 1920, bytes: 2 * 1024 * 1024),
      isFalse,
    );
    expect(
      TvClipCompress.qualityFor(height: 1920, bytes: 12 * 1024 * 1024),
      VideoQuality.Res1280x720Quality,
    );
  });

  test('катта 540p — 540p сиқиш', () {
    expect(
      TvClipCompress.qualityFor(height: 540, bytes: 8 * 1024 * 1024),
      VideoQuality.Res960x540Quality,
    );
  });

  // ── Портрет (вертикал) манба — қарор ҚИСҚА ҚИРРА бўйича ────────────
  // AVAGram лентасининг асосий формати. Аввал фақат `height` қаралар эди
  // ва портрет клипда у УЗУН қирра бўлгани учун ҳар доим "сиқиш керак"
  // деб топиларди.

  test('портрет 720x1280, кичик файл — сиқилмайди (икки марта кодлаш йўқ)',
      () {
    expect(
      TvClipCompress.shouldSkip(
        width: 720,
        height: 1280,
        bytes: 2 * 1024 * 1024,
      ),
      isTrue,
    );
  });

  test('портрет 1080x1920 — 720p га сиқилади', () {
    expect(
      TvClipCompress.shouldSkip(
        width: 1080,
        height: 1920,
        bytes: 2 * 1024 * 1024,
      ),
      isFalse,
    );
    expect(
      TvClipCompress.qualityFor(
        width: 1080,
        height: 1920,
        bytes: 12 * 1024 * 1024,
      ),
      VideoQuality.Res1280x720Quality,
    );
  });

  test('портрет 540x960, катта файл — 540p поғонаси', () {
    expect(
      TvClipCompress.qualityFor(
        width: 540,
        height: 960,
        bytes: 8 * 1024 * 1024,
      ),
      VideoQuality.Res960x540Quality,
    );
  });

  test('ландшафт 1280x720 — эски хулқ сақланади', () {
    expect(
      TvClipCompress.shouldSkip(
        width: 1280,
        height: 720,
        bytes: 2 * 1024 * 1024,
      ),
      isTrue,
    );
  });
}
