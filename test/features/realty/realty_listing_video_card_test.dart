import 'package:ava_gurlan/features/realty/widgets/realty_listing_video_card.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:ava_gurlan/features/tv_market/services/tv_clip_link.dart';
import 'package:ava_gurlan/features/tv_market/widgets/tv_clip_link_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Кўчмас мулк эълонига ИХТИЁРИЙ видео (≤ 60 с, эга қарори 2026-10-19): таҳрирдаги видео картаси
/// ва умумий қатлам қоидалари. Firebase керак эмас — боғловчилар алмаштирилади.
TvClip _clip(
  String id, {
  String status = 'active',
  String processing = 'ready',
  DateTime? at,
  String reason = '',
  String owner = '998901234567',
}) =>
    TvClip(
      id: id,
      videoUrl: 'https://x/$id.mp4',
      posterUrl: '',
      title: 'Уй $id',
      price: 0,
      districtId: 'gurlan',
      districtLabel: 'Гурлан',
      ownerPhone: owner,
      ownerName: 'Али',
      category: 'product',
      status: status,
      processingStatus: processing,
      createdAt: at ?? DateTime(2026, 10, 1),
      rejectReason: reason,
      linkKind: 'realty_listing',
      linkId: 'L1',
    );

Future<void> _pump(
  WidgetTester t, {
  required Future<List<TvClip>> Function() loader,
  Future<bool> Function()? publisher,
  Future<void> Function(TvClip)? deleter,
  void Function(TvClip)? opener,
  String me = '998901234567',
}) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: RealtyListingVideoCard(
          listingId: 'L1',
          myPhone: me,
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
  group('Умумий қатлам: realty_listing тури', () {
    test('боғлаш тури қиймати сервер/қоида билан бир хил', () {
      expect(TvClipLink.kindRealty, 'realty_listing');
    });

    test('клип realty_listing + linkId билан ёзилади (клип томонида боғлаш)', () {
      final m = _clip('c1').toMap();
      expect(m['linkKind'], 'realty_listing');
      expect(m['linkId'], 'L1');
    });

    test('60 сония: tvClipMaxSecondsFor(realty_listing) = 60, бошқа турлар ўзгармаган', () {
      expect(tvClipMaxSecondsFor('realty_listing'), 60);
      expect(tvClipMaxSecondsFor('restaurant_item'), 60);
      for (final k in ['restaurant', 'ad', 'service', 'market_ad', 'wholesale_product', '']) {
        expect(tvClipMaxSecondsFor(k), tvClipMaxUploadSeconds, reason: k);
      }
    });
  });

  group('RealtyListingVideoCard', () {
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
      expect(find.byKey(const ValueKey('realty-video-publish')), findsOneWidget);
      expect(find.byKey(const ValueKey('realty-video-status-pending')), findsNothing);

      await t.tap(find.byKey(const ValueKey('realty-video-publish')));
      await t.pumpAndSettle();

      expect(published, 1);
      expect(loads, 2);
      expect(find.byKey(const ValueKey('realty-video-status-pending')), findsOneWidget);
    });

    testWidgets('жойлаш бекор қилинса (false) рўйхат қайта юкланмайди; эълон видеосиз ҳам тўлиқ', (t) async {
      var loads = 0;
      await _pump(t, loader: () async {
        loads++;
        return <TvClip>[];
      }, publisher: () async => false);
      await t.tap(find.byKey(const ValueKey('realty-video-publish')));
      await t.pumpAndSettle();
      expect(loads, 1);
      expect(find.byKey(const ValueKey('realty-video-card')), findsOneWidget);
    });

    testWidgets('ҳар ҳолат ўз ёрлиғи билан; фаол клипда «кўриш», унга босилса opener чақирилади', (t) async {
      TvClip? opened;
      await _pump(
        t,
        loader: () async => [
          _clip('a', status: 'active', at: DateTime(2026, 10, 5)),
          _clip('b', status: 'pending', at: DateTime(2026, 10, 4)),
          _clip('c', status: 'blocked', reason: 'Сифати паст', at: DateTime(2026, 10, 3)),
          _clip('d', processing: 'error', at: DateTime(2026, 10, 2)),
        ],
        // Янгиси фаол → эскилари тозаланади; бу тестда ўчириш йиқилсин, барча ҳолатлар рўйхатда қолади.
        deleter: (_) async => throw StateError('keep'),
        opener: (c) => opened = c,
      );
      expect(find.byKey(const ValueKey('realty-video-status-active')), findsOneWidget);
      expect(find.byKey(const ValueKey('realty-video-status-pending')), findsOneWidget);
      expect(find.byKey(const ValueKey('realty-video-status-blocked')), findsOneWidget);
      expect(find.byKey(const ValueKey('realty-video-status-error')), findsOneWidget);
      expect(find.text('Сифати паст'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_outline_rounded), findsOneWidget);

      await t.tap(find.byIcon(Icons.play_circle_outline_rounded));
      expect(opened?.id, 'a');
    });

    testWidgets('янги клип жонли → ўзимнинг эски клипим автоматик ўчади (бир эълон — битта видео); бегонаники тегилмайди', (t) async {
      final removed = <String>[];
      await _pump(
        t,
        loader: () async => [
          _clip('new', at: DateTime(2026, 10, 5)),
          _clip('old', at: DateTime(2026, 10, 4)),
          _clip('colleague', at: DateTime(2026, 10, 3), owner: '998909998877'),
        ],
        deleter: (c) async => removed.add(c.id),
      );
      expect(removed, ['old']);
      expect(find.byKey(const ValueKey('realty-video-delete-old')), findsNothing);
    });

    testWidgets('ўчириш тугмаси фақат ЎЗИМ юклаган клипда; ходим юклагани — изоҳ билан', (t) async {
      await _pump(t, loader: () async => [_clip('mine'), _clip('theirs', owner: '998909998877', at: DateTime(2026, 9, 1))]);
      // theirs — янгиси эмас, эски; supersede фақат ўзимникини ўчиради, бу ерда ўчирилмаслиги керак.
      expect(find.byKey(const ValueKey('realty-video-delete-mine')), findsOneWidget);
      expect(find.byKey(const ValueKey('realty-video-delete-theirs')), findsNothing);
      expect(find.byKey(const ValueKey('realty-video-by-colleague-theirs')), findsOneWidget);
    });

    testWidgets('ўчириш: тасдиқдан кейин deleter чақирилади, рўйхат қайта юкланади; бекор қилинса — йўқ', (t) async {
      var loads = 0;
      final removed = <String>[];
      await _pump(
        t,
        loader: () async => ++loads == 1 ? [_clip('c1')] : <TvClip>[],
        deleter: (c) async => removed.add(c.id),
      );
      await t.tap(find.byKey(const ValueKey('realty-video-delete-c1')));
      await t.pumpAndSettle();
      await t.tap(find.text('cancel'));
      await t.pumpAndSettle();
      expect(removed, isEmpty);

      await t.tap(find.byKey(const ValueKey('realty-video-delete-c1')));
      await t.pumpAndSettle();
      await t.tap(find.text('realty_video_delete').last);
      await t.pumpAndSettle();
      expect(removed, ['c1']);
      expect(loads, 2);
      expect(find.byKey(const ValueKey('realty-video-delete-c1')), findsNothing);
    });

    testWidgets('юклаш хатоси: хато матни ва «қайта уриниш»; босилса қайта юклайди', (t) async {
      var loads = 0;
      await _pump(t, loader: () async {
        if (++loads == 1) throw StateError('offline');
        return <TvClip>[];
      });
      expect(find.byKey(const ValueKey('realty-video-retry')), findsOneWidget);
      expect(find.byKey(const ValueKey('realty-video-publish')), findsNothing);
      await t.tap(find.byKey(const ValueKey('realty-video-retry')));
      await t.pumpAndSettle();
      expect(loads, 2);
      expect(find.byKey(const ValueKey('realty-video-publish')), findsOneWidget);
    });
  });

  group('VideoOptionTile — матн калитлари', () {
    testWidgets('калитлар берилмаса аввалги умумий матн (бошқа модуллар ўзгармайди)', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: VideoOptionTile(value: false, onChanged: (_) {})),
      ));
      expect(find.text('link_video_optional'), findsOneWidget);
      expect(find.text('link_video_optional_hint'), findsOneWidget);
    });

    testWidgets('кўчмас мулк ўз матнини беради ва белги ўзгаришини узатади', (t) async {
      bool? v;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: VideoOptionTile(
            value: false,
            onChanged: (x) => v = x,
            titleKey: 'realty_video_option',
            hintKey: 'realty_video_option_hint',
          ),
        ),
      ));
      expect(find.text('realty_video_option'), findsOneWidget);
      await t.tap(find.byType(CheckboxListTile));
      expect(v, isTrue);
    });
  });
}
