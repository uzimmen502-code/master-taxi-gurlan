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

  test('45с қисқартирилмайди, 90с → 60с', () {
    expect(TvClipCompress.clipDurationSeconds(45000), isNull);
    expect(TvClipCompress.clipDurationSeconds(90), 60);
    expect(TvClipCompress.clipDurationSeconds(120000), 60);
  });
}
