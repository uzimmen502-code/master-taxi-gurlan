import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:ava_gurlan/features/tv_market/utils/tv_news_unread.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «Кун янгиликлари» табидаги ўқилмаганлик нуқтаси (эга қарори, 2026-10-24): қурилмада сақланади.
TvClip _clip(
  String id, {
  String category = 'news',
  String status = 'active',
  String owner = '998901112233',
  DateTime? createdAt,
  DateTime? expiresAt,
  String processingStatus = '',
}) =>
    TvClip.fromMap(id, {
      'videoUrl': 'https://x/v.mp4',
      'posterUrl': 'https://x/p.jpg',
      'title': id,
      'category': category,
      'status': status,
      'ownerPhone': owner,
      'districtId': 'gurlan',
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt),
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
      if (processingStatus.isNotEmpty) 'processingStatus': processingStatus,
    });

void main() {
  final now = DateTime.utc(2026, 10, 24, 12);
  DateTime ago(int h) => now.subtract(Duration(hours: h));

  group('newestVisibleNewsAt', () {
    test('энг сўнгги янгилик вақти қайтади', () {
      final r = newestVisibleNewsAt(
        [_clip('a', createdAt: ago(5)), _clip('b', createdAt: ago(1)), _clip('c', createdAt: ago(9))],
        mePhone: '998907777777',
        now: now,
      );
      expect(r!.isAtSameMomentAs(ago(1)), isTrue);
    });

    test('ўзимнинг янгилигим, бошқа category, ўчган, муддати тугаган, ўйнатилмайдиган — ҳисобга кирмайди', () {
      final r = newestVisibleNewsAt(
        [
          _clip('own', owner: '+998 90 777 77 77', createdAt: ago(1)),
          _clip('ad', category: 'ad', createdAt: ago(1)),
          _clip('deleted', status: 'deleted', createdAt: ago(1)),
          _clip('expired', createdAt: ago(1), expiresAt: ago(0)),
          _clip('broken', createdAt: ago(1), processingStatus: 'error'),
          _clip('ok', createdAt: ago(7)),
        ],
        mePhone: '998907777777',
        now: now,
      );
      expect(r!.isAtSameMomentAs(ago(7)), isTrue, reason: 'фақат «ok» кўринади');
    });

    test('createdAt йўқ ёки рўйхат бўш — null', () {
      expect(newestVisibleNewsAt([_clip('x')], mePhone: '', now: now), isNull);
      expect(newestVisibleNewsAt(const [], mePhone: '', now: now), isNull);
    });
  });

  group('tvNewsHasUnread', () {
    test('янгилик йўқ — нуқта йўқ', () {
      expect(tvNewsHasUnread(latest: null, seen: null), isFalse);
      expect(tvNewsHasUnread(latest: null, seen: ago(2)), isFalse);
    });

    test('ҳеч қачон очилмаган — янгилик бор бўлса нуқта', () {
      expect(tvNewsHasUnread(latest: ago(1), seen: null), isTrue);
    });

    test('чегара: кўрилгандан кейин чиққан — нуқта; айнан шу вақт ёки эскироқ — йўқ', () {
      expect(tvNewsHasUnread(latest: ago(1), seen: ago(2)), isTrue);
      expect(tvNewsHasUnread(latest: ago(2), seen: ago(2)), isFalse);
      expect(tvNewsHasUnread(latest: ago(3), seen: ago(2)), isFalse);
    });
  });

  group('TvNewsSeenStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('бошида бўш; ёзилган вақт ўқилади', () async {
      expect(await TvNewsSeenStore.read(), isNull);
      await TvNewsSeenStore.markSeen(ago(3));
      expect((await TvNewsSeenStore.read())!.isAtSameMomentAs(ago(3)), isTrue);
    });

    test('фақат олдинга силжийди (эскироқ вақт ёзилмайди)', () async {
      await TvNewsSeenStore.markSeen(ago(2));
      await TvNewsSeenStore.markSeen(ago(6));
      expect((await TvNewsSeenStore.read())!.isAtSameMomentAs(ago(2)), isTrue);
      await TvNewsSeenStore.markSeen(ago(1));
      expect((await TvNewsSeenStore.read())!.isAtSameMomentAs(ago(1)), isTrue);
    });
  });
}
