import 'package:ava_gurlan/features/jobs/screens/jobs_screen.dart';
import 'package:ava_gurlan/models/job_ad.dart';
import 'package:flutter_test/flutter_test.dart';

JobAd _ad(String id) => JobAd(
      id: id,
      type: 'ad',
      text: 'матн $id',
      title: 'эълон $id',
      priceText: '',
      authorName: 'Эга',
      authorPhone: '998901234567',
      address: '',
      isUrgent: false,
      status: 'active',
      expiresAt: null,
    );

void main() {
  group('jobsFeedWithHighlightFirst — бош саҳифадан келган эълон', () {
    test('босилган эълон рўйхат ТЕПАСИГА чиқади', () {
      final feed = [_ad('a'), _ad('b'), _ad('c')];
      final out = jobsFeedWithHighlightFirst(feed, 'c');
      expect(out.map((e) => e.id).toList(), ['c', 'a', 'b']);
    });

    test('қолган эълонлар тартиби бузилмайди', () {
      final feed = [_ad('a'), _ad('b'), _ad('c'), _ad('d')];
      final out = jobsFeedWithHighlightFirst(feed, 'c');
      expect(out.map((e) => e.id).toList(), ['c', 'a', 'b', 'd']);
    });

    test('аллақачон биринчи бўлса — рўйхат ўзгармайди', () {
      final feed = [_ad('a'), _ad('b')];
      final out = jobsFeedWithHighlightFirst(feed, 'a');
      expect(identical(out, feed), isTrue);
    });

    test('эълон топилмаса (муддати тугаган/ўчирилган) — рўйхат ўзгармайди',
        () {
      final feed = [_ad('a'), _ad('b')];
      final out = jobsFeedWithHighlightFirst(feed, 'yoq');
      expect(identical(out, feed), isTrue);
    });

    test('бўш id — рўйхат ўзгармайди', () {
      final feed = [_ad('a'), _ad('b')];
      expect(identical(jobsFeedWithHighlightFirst(feed, ''), feed), isTrue);
    });

    test('бўш рўйхат — йиқилмайди', () {
      expect(jobsFeedWithHighlightFirst(const <JobAd>[], 'a'), isEmpty);
    });
  });
}
