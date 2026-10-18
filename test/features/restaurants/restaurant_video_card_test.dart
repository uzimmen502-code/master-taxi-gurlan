import 'package:ava_gurlan/features/restaurants/merchant/restaurant_video_card.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:ava_gurlan/features/tv_market/services/tv_clip_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TvClip _clip(
  String id, {
  String status = 'active',
  String processing = 'ready',
  DateTime? at,
  String reason = '',
}) =>
    TvClip(
      id: id,
      videoUrl: 'https://x/$id.mp4',
      posterUrl: '',
      title: 'Обзор $id',
      price: 0,
      districtId: 'gurlan',
      districtLabel: 'Гурлан',
      ownerPhone: '998901234567',
      ownerName: 'Али',
      category: 'product',
      status: status,
      processingStatus: processing,
      createdAt: at ?? DateTime(2026, 10, 1),
      rejectReason: reason,
      linkKind: 'restaurant',
      linkId: 'r1',
    );

Future<void> _pump(
  WidgetTester t, {
  required Future<List<TvClip>> Function() loader,
  Future<bool> Function()? publisher,
  Future<void> Function(TvClip)? deleter,
  void Function(TvClip)? opener,
  bool approved = true,
}) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: RestaurantVideoCard(
          restaurantId: 'r1',
          ownerPhone: '998901234567',
          restaurantApproved: approved,
          loader: loader,
          publisher: publisher,
          deleter: deleter,
          opener: opener,
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  group('TvClipLink.supersededClips / statusKey (соф қоидалар)', () {
    test('янгиси жонли → эскилари ортиқча', () {
      final list = [_clip('new', status: 'active'), _clip('old', status: 'active')];
      expect(TvClipLink.supersededClips(list).map((c) => c.id), ['old']);
    });

    test('янгиси текширувда → ҳеч нарса ўчирилмайди (мижозда эскиси кўринади)', () {
      final list = [_clip('new', status: 'pending'), _clip('old', status: 'active')];
      expect(TvClipLink.supersededClips(list), isEmpty);
    });

    test('янгиси рад этилган ёки transcode хато → эскиси сақланади', () {
      expect(TvClipLink.supersededClips([_clip('n', status: 'blocked'), _clip('o')]), isEmpty);
      expect(TvClipLink.supersededClips([_clip('n', processing: 'error'), _clip('o')]), isEmpty);
    });

    test('битта ёки бўш рўйхат', () {
      expect(TvClipLink.supersededClips([_clip('a')]), isEmpty);
      expect(TvClipLink.supersededClips(const []), isEmpty);
    });

    test('ҳолат калити', () {
      expect(TvClipLink.statusKey(_clip('a')), 'active');
      expect(TvClipLink.statusKey(_clip('a', status: 'pending')), 'pending');
      expect(TvClipLink.statusKey(_clip('a', status: 'blocked')), 'blocked');
      expect(TvClipLink.statusKey(_clip('a', status: 'expired')), 'other');
      expect(TvClipLink.statusKey(_clip('a', processing: 'error')), 'error');
    });
  });

  group('RestaurantVideoCard', () {
    testWidgets('видео йўқ: «қўшиш» тугмаси, босилса умумий жойлаш чақирилади ва рўйхат қайта юкланади', (t) async {
      var loads = 0;
      var published = 0;
      await _pump(
        t,
        loader: () async => ++loads == 1 ? <TvClip>[] : [_clip('c1', status: 'pending')],
        publisher: () async {
          published++;
          return true;
        },
      );
      expect(find.byKey(const ValueKey('video-publish')), findsOneWidget);
      expect(find.byKey(const ValueKey('video-status-pending')), findsNothing);

      await t.tap(find.byKey(const ValueKey('video-publish')));
      await t.pumpAndSettle();

      expect(published, 1);
      expect(loads, 2);
      expect(find.byKey(const ValueKey('video-status-pending')), findsOneWidget);
    });

    testWidgets('жойлаш бекор қилинса (false) рўйхат қайта юкланмайди', (t) async {
      var loads = 0;
      await _pump(t, loader: () async {
        loads++;
        return <TvClip>[];
      }, publisher: () async => false);
      await t.tap(find.byKey(const ValueKey('video-publish')));
      await t.pumpAndSettle();
      expect(loads, 1);
    });

    testWidgets('ҳар ҳолат ўз ёрлиғи билан; рад сабаби кўринади; фақат фаол клипда «кўриш»', (t) async {
      await _pump(
        t,
        loader: () async => [
          _clip('a', status: 'active', at: DateTime(2026, 10, 5)),
          _clip('b', status: 'pending', at: DateTime(2026, 10, 4)),
          _clip('c', status: 'blocked', reason: 'Сифати паст', at: DateTime(2026, 10, 3)),
          _clip('d', processing: 'error', at: DateTime(2026, 10, 2)),
        ],
        // Янгиси фаол → эскилари тозаланади; бу тестда ўчириш йиқилсин, шунда
        // барча ҳолатлар рўйхатда қолади ва ёрлиқлари текширилади.
        deleter: (_) async => throw StateError('keep'),
      );
      expect(find.byKey(const ValueKey('video-status-active')), findsOneWidget);
      expect(find.byKey(const ValueKey('video-status-pending')), findsOneWidget);
      expect(find.byKey(const ValueKey('video-status-blocked')), findsOneWidget);
      expect(find.byKey(const ValueKey('video-status-error')), findsOneWidget);
      expect(find.text('Сифати паст'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_outline_rounded), findsOneWidget);
    });

    testWidgets('янги видео жонли бўлса эскилари ўчирилади, ўчириш йиқилса қолади', (t) async {
      final deleted = <String>[];
      await _pump(
        t,
        loader: () async => [
          _clip('new', at: DateTime(2026, 10, 9)),
          _clip('old1', at: DateTime(2026, 10, 2)),
          _clip('old2', at: DateTime(2026, 10, 1)),
        ],
        deleter: (c) async {
          if (c.id == 'old2') throw StateError('fail');
          deleted.add(c.id);
        },
      );
      expect(deleted, ['old1']);
      expect(find.byKey(const ValueKey('video-delete-new')), findsOneWidget);
      expect(find.byKey(const ValueKey('video-delete-old1')), findsNothing);
      expect(find.byKey(const ValueKey('video-delete-old2')), findsOneWidget);
    });

    testWidgets('ўчириш: тасдиқдан кейингина ўчади ва рўйхат янгиланади', (t) async {
      final deleted = <String>[];
      var loads = 0;
      await _pump(
        t,
        loader: () async => ++loads == 1 ? [_clip('c1')] : <TvClip>[],
        deleter: (c) async => deleted.add(c.id),
      );
      await t.tap(find.byKey(const ValueKey('video-delete-c1')));
      await t.pumpAndSettle();
      expect(deleted, isEmpty, reason: 'тасдиқ диалоги чиқди, ҳали ўчмади');

      await t.tap(find.byType(FilledButton));
      await t.pumpAndSettle();
      expect(deleted, ['c1']);
      expect(find.byKey(const ValueKey('video-delete-c1')), findsNothing);
    });

    testWidgets('ўчиришни бекор қилиш — ҳеч нарса ўчмайди', (t) async {
      final deleted = <String>[];
      await _pump(t, loader: () async => [_clip('c1')], deleter: (c) async => deleted.add(c.id));
      await t.tap(find.byKey(const ValueKey('video-delete-c1')));
      await t.pumpAndSettle();
      await t.tap(find.byType(TextButton));
      await t.pumpAndSettle();
      expect(deleted, isEmpty);
      expect(find.byKey(const ValueKey('video-delete-c1')), findsOneWidget);
    });

    testWidgets('юклаш хатоси: «Қайта уриниш» ишлайди', (t) async {
      var calls = 0;
      await _pump(t, loader: () async {
        if (++calls == 1) throw StateError('offline');
        return [_clip('c1')];
      });
      expect(find.byKey(const ValueKey('video-retry')), findsOneWidget);
      expect(find.byKey(const ValueKey('video-publish')), findsNothing);

      await t.tap(find.byKey(const ValueKey('video-retry')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('video-status-active')), findsOneWidget);
    });

    testWidgets('«кўриш» босилса шу клип очилади', (t) async {
      TvClip? opened;
      await _pump(t, loader: () async => [_clip('c1')], opener: (c) => opened = c);
      await t.tap(find.byIcon(Icons.play_circle_outline_rounded));
      expect(opened?.id, 'c1');
    });

    testWidgets('ресторан тасдиқланмаган бўлса огоҳлантириш қатори бор, тасдиқланган бўлса йўқ', (t) async {
      await _pump(t, loader: () async => <TvClip>[], approved: false);
      final withNote = find.byType(Text).evaluate().length;
      await _pump(t, loader: () async => <TvClip>[], approved: true);
      final without = find.byType(Text).evaluate().length;
      expect(withNote, without + 1);
    });
  });
}
