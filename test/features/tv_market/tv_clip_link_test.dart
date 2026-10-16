import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:ava_gurlan/features/tv_market/services/tv_clip_link.dart';
import 'package:ava_gurlan/features/tv_market/widgets/tv_clip_link_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Эълон / хизмат / Аҳоли бозори / ресторанга ИХТИЁРИЙ видео (эга, 2026-10-16).
/// Боғланиш клип томонида (`linkKind`/`linkId`), эълон ҳужжати ва сервер
/// ўзгармайди.
TvClip _clip({
  String id = 'c1',
  String owner = '998901234567',
  String linkKind = '',
  String linkId = '',
}) =>
    TvClip(
      id: id,
      videoUrl: 'https://x/v.mp4',
      posterUrl: '',
      title: 'Обзор',
      price: 0,
      districtId: 'gurlan',
      districtLabel: 'Гурлан',
      ownerPhone: owner,
      ownerName: 'Али',
      category: 'product',
      linkKind: linkKind,
      linkId: linkId,
    );

void main() {
  group('TvClip.linkKind / linkId', () {
    test('боғланмаган клип: майдонлар ёзилмайди (эски ҳужжат шакли ўзгармайди)', () {
      final m = _clip().toMap();
      expect(m.containsKey('linkKind'), isFalse);
      expect(m.containsKey('linkId'), isFalse);
    });

    test('боғланган клип: иккови ҳам ёзилади', () {
      final m = _clip(linkKind: 'ad', linkId: 'A1').toMap();
      expect(m['linkKind'], 'ad');
      expect(m['linkId'], 'A1');
    });

    test('ярим боғланиш (фақат kind ёки фақат id) ёзилмайди', () {
      expect(_clip(linkKind: 'ad').toMap().containsKey('linkKind'), isFalse);
      expect(_clip(linkId: 'A1').toMap().containsKey('linkId'), isFalse);
    });

    test('copyWith (лайк/кўриш янгиланиши) боғланишни ЙЎҚОТМАЙДИ', () {
      final c = _clip(linkKind: 'restaurant', linkId: 'R1').copyWith(likeCount: 5);
      expect(c.linkKind, 'restaurant');
      expect(c.linkId, 'R1');
      expect(c.likeCount, 5);
    });
  });

  group('TvClipLink.ownedClip — бегона боғлашдан ҳимоя', () {
    test('клип эгаси = эълон эгаси — кўринади (9/12 хонали формат фарқи ҳисобга олинмайди)', () {
      final linked = {'A1': _clip(linkKind: 'ad', linkId: 'A1')};
      expect(TvClipLink.ownedClip(linked, 'A1', '998901234567')?.id, 'c1');
      expect(TvClipLink.ownedClip(linked, 'A1', '+998 90 123 45 67')?.id, 'c1');
    });

    test('БОШҚА одамнинг клипи чужой эълонга боғланган — кўрсатилмайди', () {
      final linked = {'A1': _clip(owner: '998909999999', linkKind: 'ad', linkId: 'A1')};
      expect(TvClipLink.ownedClip(linked, 'A1', '998901234567'), isNull);
    });

    test('боғланган клип йўқ — null', () {
      expect(TvClipLink.ownedClip(const {}, 'A1', '998901234567'), isNull);
    });
  });

  group('VideoOptionTile', () {
    testWidgets('бошланғич белгисиз, босилса callback true/false', (t) async {
      var value = false;
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => VideoOptionTile(
              value: value,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ));
      expect(find.text('link_video_optional'), findsOneWidget);
      expect(find.text('link_video_optional_hint'), findsOneWidget);
      expect(isChecked(t), isFalse);
      await t.tap(find.byType(CheckboxListTile));
      await t.pump();
      expect(value, isTrue);
      expect(isChecked(t), isTrue);
      await t.tap(find.byType(CheckboxListTile));
      await t.pump();
      expect(value, isFalse);
    });
  });

  group('LinkedVideoButton', () {
    Future<int> pump(WidgetTester t, Future<TvClip?> Function() loader) async {
      var builds = 0;
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              builds++;
              return Column(children: [
                LinkedVideoButton(
                  linkId: 'A1',
                  ownerPhone: '998901234567',
                  loader: loader,
                ),
                TextButton(onPressed: () => setState(() {}), child: const Text('rebuild')),
              ]);
            },
          ),
        ),
      ));
      await t.pumpAndSettle();
      return builds;
    }

    testWidgets('видео бор — «Видеони кўриш» тугмаси чиқади', (t) async {
      await pump(t, () async => _clip(linkKind: 'ad', linkId: 'A1'));
      expect(find.text('link_video_open'), findsOneWidget);
    });

    testWidgets('видео йўқ — ҳеч нарса (жой эгалламайди)', (t) async {
      await pump(t, () async => null);
      expect(find.text('link_video_open'), findsNothing);
    });

    testWidgets('юклаш хатоси экранни йиқитмайди', (t) async {
      await pump(t, () async => throw StateError('offline'));
      expect(find.text('link_video_open'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('ота виджет қайта қурилганда сўров ҚАЙТА юборилмайди (36-қоида)', (t) async {
      var calls = 0;
      await pump(t, () async {
        calls++;
        return _clip(linkKind: 'ad', linkId: 'A1');
      });
      expect(calls, 1);
      await t.tap(find.text('rebuild'));
      await t.pumpAndSettle();
      await t.tap(find.text('rebuild'));
      await t.pumpAndSettle();
      expect(calls, 1);
    });
  });
}

bool isChecked(WidgetTester t) =>
    t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value ?? false;
