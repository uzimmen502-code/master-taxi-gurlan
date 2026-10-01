import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ava_gurlan/features/tv_market/utils/tv_playback_sampling.dart';

void main() {
  group('tvShouldWritePlaybackStats — қарор', () {
    test('rate 1.0 — ҳар доим ёзилади', () {
      for (final r in [0.0, 0.5, 0.999999]) {
        expect(tvShouldWritePlaybackStats(r, rate: 1.0), isTrue);
      }
    });

    test('rate 0.0 — ҳеч қачон ёзилмайди', () {
      for (final r in [0.0, 0.5, 0.999999]) {
        expect(tvShouldWritePlaybackStats(r, rate: 0.0), isFalse);
      }
    });

    test('чегара: roll < rate ўтади, roll == rate ўтмайди', () {
      expect(tvShouldWritePlaybackStats(0.0999, rate: 0.1), isTrue);
      expect(tvShouldWritePlaybackStats(0.1, rate: 0.1), isFalse);
      expect(tvShouldWritePlaybackStats(0.1001, rate: 0.1), isFalse);
    });
  });

  group('намуна улуши — ўртачалар бузилмаслиги учун', () {
    test('қабул қилинганлар улуши rate га яқин', () {
      // Детерминистик уруғ — тест «баъзан» йиқилмайди.
      final rng = Random(12345);
      const n = 200000;
      var kept = 0;
      for (var i = 0; i < n; i++) {
        if (tvShouldWritePlaybackStats(rng.nextDouble())) kept++;
      }
      final share = kept / n;
      // 200k да 10% учун статистик хато ~0.07%; 0.5% чегара кенг запас.
      expect(
        (share - kTvPlaybackStatsSampleRate).abs() < 0.005,
        isTrue,
        reason: 'улуш $share, кутилган $kTvPlaybackStatsSampleRate',
      );
    });

    test('намуна ЎРТАЧАНИ силжитмайди', () {
      // Ҳар playback'га «томоша вақти» берамиз ва намунадаги ўртача
      // тўлиқ тўпламникига яқин чиқишини текширамиз. Айнан шу хусусият
      // туфайли `audit_avagram_usage.js` намунадан ўртача ҳисоблай олади.
      final rng = Random(777);
      var allSum = 0.0;
      var allN = 0;
      var sampleSum = 0.0;
      var sampleN = 0;
      for (var i = 0; i < 200000; i++) {
        final watched = rng.nextDouble() * 60000; // 0..60 с
        allSum += watched;
        allN++;
        if (tvShouldWritePlaybackStats(rng.nextDouble())) {
          sampleSum += watched;
          sampleN++;
        }
      }
      final all = allSum / allN;
      final sample = sampleSum / sampleN;
      expect(
        (sample - all).abs() / all < 0.02,
        isTrue,
        reason: 'тўлиқ ўртача $all, намунадагиси $sample',
      );
    });
  });

  test('клиент ва аудит скриптидаги намуна улуши мос', () {
    // Мослик бузилса аудит абсолют сонларни нотўғри миқёслайди —
    // «видеодан воз кечайликми?» қарори бузуқ рақамга таянарди.
    final js =
        File('functions/tools/audit_avagram_usage.js').readAsStringSync();
    final m = RegExp(r'const PLAYBACK_STATS_SAMPLE_RATE = ([\d.]+);')
        .firstMatch(js);
    expect(m, isNotNull,
        reason: 'audit_avagram_usage.js: PLAYBACK_STATS_SAMPLE_RATE йўқ');
    expect(double.parse(m!.group(1)!), kTvPlaybackStatsSampleRate);
  });
}
