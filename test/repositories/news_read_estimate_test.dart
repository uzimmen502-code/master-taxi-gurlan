import 'package:ava_gurlan/models/news_item.dart';
import 'package:ava_gurlan/repositories/news_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Хабарлар» таб белгиси ёниб-ўчиши (эга, 2026-10-26): таб босилганда `lastXReadAt = serverTimestamp()` ёзилади,
/// сервер тасдиқлагунча маҳаллий нусхада майдон бор, қиймати `null` — аввал «ҳаммаси ўқилмаган» деб саналарди.
void main() {
  final now = DateTime(2026, 10, 26, 13, 0);
  final items = [
    NewsItem(id: 'a', title: '', body: '', createdAt: DateTime(2026, 10, 26, 10, 18)),
    NewsItem(id: 'b', title: '', body: '', createdAt: DateTime(2026, 7, 18, 14, 53)),
  ];

  test('сервер вақти кутилмоқда (майдон бор, null) — «ҳозир» деб баҳоланади, белги 0', () {
    final est = NewsRepository.pendingServerTimeEstimate({'lastMessagesReadAt': null}, 'lastMessagesReadAt', now: now);
    expect(est, now);
    expect(NewsRepository.countUnreadInList(items, est), 0);
  });

  test('майдон умуман йўқ (ҳеч ўқилмаган) — баҳоланмайди, ҳаммаси ўқилмаган (аввалги хулқ)', () {
    final est = NewsRepository.pendingServerTimeEstimate({'name': 'x'}, 'lastMessagesReadAt', now: now);
    expect(est, isNull);
    expect(NewsRepository.countUnreadInList(items, est), 2);
  });

  test('ҳужжат йўқ — баҳоланмайди', () {
    expect(NewsRepository.pendingServerTimeEstimate(null, 'lastOrderNewsReadAt', now: now), isNull);
  });
}
