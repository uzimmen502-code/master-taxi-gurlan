import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:ava_gurlan/features/tv_market/widgets/tv_clip_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _ownerName = 'Аваз Собиров';

TvClip _clip({bool showPhone = true}) => TvClip(
      id: 'c1',
      videoUrl: 'https://example.test/a.mp4',
      posterUrl: '',
      title: 'Сотилади',
      price: 0,
      districtId: 'd1',
      districtLabel: 'Гурлан',
      ownerPhone: '+998900000000',
      ownerName: _ownerName,
      category: 'product',
      showPhone: showPhone,
    );

Future<void> _pump(
  WidgetTester tester, {
  Widget? filters,
  bool isOwner = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            TvClipOverlay(
              clip: _clip(),
              isOwner: isOwner,
              filters: filters,
              onContact: () {},
              onLike: () {},
              onComment: () {},
              onShare: () {},
              onSave: () {},
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('«Боғланиш» бутун кенгликка чўзилмайди — матн кенглигида',
      (tester) async {
    // Тугма матн кенглигида бўлса, бўш жой кўпайганда ҳам ўлчами
    // ўзгармайди. Аввалги `width: double.infinity` эса экран билан
    // бирга кенгаярди. Шрифт кенглигига боғлиқ бўлмаган текширув.
    await _pump(tester);
    final narrow = tester.getSize(find.byType(ElevatedButton)).width;

    await tester.binding.setSurfaceSize(const Size(800, 800));
    await tester.pump();
    final wide = tester.getSize(find.byType(ElevatedButton)).width;

    expect(wide, closeTo(narrow, 0.5),
        reason: 'экран 400→800 бўлганда тугма $narrow→$wide px — '
            'демак у чўзилиб турибди');
    // Ва мавжуд жойдан (800 - 12 - 72 = 716) анча тор.
    expect(wide, lessThan(400));
  });

  testWidgets('фильтрлар ва «Боғланиш» битта қаторда — вертикал маркази бир хил',
      (tester) async {
    await _pump(
      tester,
      filters: const SizedBox(key: Key('filters'), width: 120, height: 30),
    );

    final filters = find.byKey(const Key('filters'));
    final btn = find.byType(ElevatedButton);
    expect(filters, findsOneWidget);
    expect(btn, findsOneWidget);

    // Битта Row'да бўлса маркази бир хил баландликда туради.
    expect(
      tester.getCenter(filters).dy,
      closeTo(tester.getCenter(btn).dy, 1.0),
    );
    // Фильтрлар чапда, тугма ўнгда.
    expect(tester.getCenter(filters).dx, lessThan(tester.getCenter(btn).dx));
  });

  testWidgets('эга исми overlay\'да энди кўрсатилмайди (AppBar\'га кўчди)',
      (tester) async {
    await _pump(tester);
    expect(find.text(_ownerName), findsNothing);
  });

  testWidgets('эганинг ўз клипида «Боғланиш» йўқ, фильтрлар эса бор',
      (tester) async {
    await _pump(
      tester,
      isOwner: true,
      filters: const SizedBox(key: Key('filters'), width: 120, height: 30),
    );
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byKey(const Key('filters')), findsOneWidget);
  });
}
