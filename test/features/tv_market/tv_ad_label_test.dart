import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:ava_gurlan/features/tv_market/utils/tv_clip_shuffle.dart';
import 'package:ava_gurlan/features/tv_market/widgets/tv_ad_label.dart';
import 'package:ava_gurlan/features/tv_market/widgets/tv_clip_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 8-босқич (2026-10-25): пуллик реклама томошабинга очиқ «Реклама» деб белгиланади;
/// юқори тариф лента бошига чиқади, ортиқчаси эса ўз ўрнида қолади (охирга тушмайди).
TvClip _clip(String id, {String category = 'product', String tier = ''}) => TvClip(
      id: id,
      videoUrl: 'https://example.test/$id.mp4',
      posterUrl: '',
      title: 'Клип $id',
      price: 0,
      districtId: 'd1',
      districtLabel: 'Гурлан',
      ownerPhone: '998900000000',
      ownerName: 'Аваз',
      category: category,
      adTier: tier,
    );

Future<void> _overlay(WidgetTester tester, TvClip clip) async {
  await tester.binding.setSurfaceSize(const Size(400, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Stack(children: [
        TvClipOverlay(
          clip: clip,
          isOwner: false,
          onContact: () {},
          onLike: () {},
          onComment: () {},
          onShare: () {},
          onSave: () {},
        ),
      ]),
    ),
  ));
}

void main() {
  group('«Реклама» белгиси', () {
    testWidgets('тўлиқ экран: пуллик реклама — белги бор, сарлавҳадан юқорида', (tester) async {
      await _overlay(tester, _clip('a', category: 'ad', tier: 'basic'));
      final label = find.byKey(const ValueKey('tv_ad_label'));
      expect(label, findsOneWidget);
      expect(tester.getCenter(label).dy, lessThan(tester.getCenter(find.text('Клип a')).dy));
    });

    testWidgets('оддий товар/хизмат/янгилик — белги йўқ', (tester) async {
      for (final cat in ['product', 'service', 'news']) {
        await _overlay(tester, _clip('b', category: cat));
        expect(find.byKey(const ValueKey('tv_ad_label')), findsNothing, reason: cat);
      }
    });

    testWidgets('виджетнинг ўзи реклама бўлмаса ҳеч нарса чизмайди; экран ўқувчиси учун ном бор', (tester) async {
      await tester.pumpWidget(MaterialApp(home: TvAdLabel(clip: _clip('c'))));
      expect(find.byKey(const ValueKey('tv_ad_label')), findsNothing);
      await tester.pumpWidget(MaterialApp(home: TvAdLabel(clip: _clip('d', category: 'ad'), compact: true)));
      expect(find.byKey(const ValueKey('tv_ad_label')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('tv_ad_label|Реклама')), findsOneWidget);
    });
  });

  group('tvApplyAdTierPriority', () {
    List<String> ids(List<TvClip> l) => [for (final c in l) c.id];

    test('юқори тариф бошда (pro_max → premium → home → visibility); basic кўтарилмайди', () {
      final out = tvApplyAdTierPriority([
        _clip('o1'),
        _clip('v', category: 'ad', tier: 'visibility'),
        _clip('b', category: 'ad', tier: 'basic'),
        _clip('p', category: 'ad', tier: 'pro_max'),
        _clip('o2'),
        _clip('h', category: 'ad', tier: 'home'),
      ]);
      expect(ids(out), ['p', 'h', 'v', 'o1', 'b', 'o2']);
    });

    test('REGRESSION: слотдан ортиқ пуллик клип ўз ўрнида қолади, лента охирига тушмайди', () {
      final items = [
        for (var i = 0; i < 3; i++) _clip('ad$i', category: 'ad', tier: 'premium'),
        _clip('o1'),
        _clip('extra', category: 'ad', tier: 'visibility'),
        _clip('o2'),
        _clip('o3'),
      ];
      final out = tvApplyAdTierPriority(items, maxBoostedSlots: 3);
      expect(ids(out), ['ad0', 'ad1', 'ad2', 'o1', 'extra', 'o2', 'o3']);
      expect(out.length, items.length, reason: 'ҳеч бир клип йўқолмайди ва такрорланмайди');
    });

    test('пуллик клип йўқ — тартиб ўзгармайди', () {
      final items = [_clip('x'), _clip('y'), _clip('z')];
      expect(ids(tvApplyAdTierPriority(items)), ['x', 'y', 'z']);
    });
  });
}
