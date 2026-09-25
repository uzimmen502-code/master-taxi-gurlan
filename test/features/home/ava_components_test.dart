import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/home/widgets/ava_card.dart';
import 'package:ava_gurlan/features/home/widgets/ava_chip.dart';
import 'package:ava_gurlan/features/home/widgets/ava_list_row.dart';
import 'package:ava_gurlan/features/home/widgets/ava_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Виджетни берилган кенглик ва шрифт масштабида чизади.
///
/// [width] 320 — иловадаги энг тор реал экран; [scale] 1.3 — тавсифдаги
/// «шрифт 130% гача катталаштирилганда кесилмаслиги керак» талаби.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 360,
  double scale = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('AvaSection — тўртта ҳолат', () {
    testWidgets('ready — мазмун кўрсатилади', (tester) async {
      await _pump(
        tester,
        const AvaSection(
          title: 'Яқинингиздаги эълонлар',
          status: AvaSectionStatus.ready,
          child: Text('МАЗМУН'),
        ),
      );
      expect(find.text('Яқинингиздаги эълонлар'), findsOneWidget);
      expect(find.text('МАЗМУН'), findsOneWidget);
    });

    testWidgets('empty — бўлим ўз ўрнида қолади, сарлавҳа кўринади',
        (tester) async {
      await _pump(
        tester,
        const AvaSection(
          title: 'Шаҳарлараро такси',
          status: AvaSectionStatus.empty,
          emptyLabel: 'Ҳозирча таклиф йўқ',
          child: Text('МАЗМУН'),
        ),
      );
      // Тавсиф талаби: бўш бўлим йўқолиб кетмайди.
      expect(find.text('Шаҳарлараро такси'), findsOneWidget);
      expect(find.text('Ҳозирча таклиф йўқ'), findsOneWidget);
      expect(find.text('МАЗМУН'), findsNothing);
    });

    testWidgets('loading — мазмун ҳам, бўш матн ҳам чиқмайди', (tester) async {
      await _pump(
        tester,
        const AvaSection(
          title: 'Юк машиналари',
          status: AvaSectionStatus.loading,
          emptyLabel: 'Ҳозирча таклиф йўқ',
          child: Text('МАЗМУН'),
        ),
      );
      expect(find.text('МАЗМУН'), findsNothing);
      expect(find.text('Ҳозирча таклиф йўқ'), findsNothing);
    });

    testWidgets('error — қайта уриниш чақирилади', (tester) async {
      var retried = 0;
      await _pump(
        tester,
        AvaSection(
          title: 'Аҳоли бозори',
          status: AvaSectionStatus.error,
          onRetry: () => retried++,
          child: const Text('МАЗМУН'),
        ),
      );
      expect(find.text('МАЗМУН'), findsNothing);
      await tester.tap(find.text('home_section_retry'));
      expect(retried, 1);
    });
  });

  group('«Барчаси →»', () {
    testWidgets('onSeeAll йўқ бўлса тугма ҳам йўқ', (tester) async {
      await _pump(
        tester,
        const AvaSection(
          title: 'Танишув',
          status: AvaSectionStatus.ready,
          child: SizedBox.shrink(),
        ),
      );
      expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
    });

    testWidgets('босиш майдони камида 44', (tester) async {
      await _pump(
        tester,
        AvaSection(
          title: 'AVAGram',
          status: AvaSectionStatus.ready,
          onSeeAll: () {},
          child: const SizedBox.shrink(),
        ),
      );
      final box = tester.getSize(
        find.ancestor(
          of: find.byIcon(Icons.arrow_forward_rounded),
          matching: find.byType(ConstrainedBox),
        ).first,
      );
      expect(box.height, greaterThanOrEqualTo(44.0));
    });
  });

  group('130% шрифтда кесилиш йўқ', () {
    testWidgets('AvaListRow — узун сарлавҳа + нарх, 320px', (tester) async {
      await _pump(
        tester,
        const AvaListRow(
          title: 'Жуда узун эълон сарлавҳаси, ҳақиқатан ҳам узун матн',
          subtitle: 'Гурлан тумани · 2 соат олдин',
          price: '1 250 000 сўм',
          priceNote: 'ўрин',
        ),
        width: 320,
        scale: 1.3,
      );
      expect(tester.takeException(), isNull);
      // Нарх қирқилмаган — тўлиқ матн топилади.
      expect(find.text('1 250 000 сўм'), findsOneWidget);
    });

    testWidgets('AvaSection сарлавҳаси + «Барчаси», 320px', (tester) async {
      await _pump(
        tester,
        AvaSection(
          title: 'Яқинингиздаги хизмат таклифлари',
          status: AvaSectionStatus.ready,
          onSeeAll: () {},
          child: const SizedBox.shrink(),
        ),
        width: 320,
        scale: 1.3,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('AvaTileCard — узун ном ва нарх, 148px', (tester) async {
      await _pump(
        tester,
        const AvaTileCard(
          title: 'Ўзбекистонда ишлаб чиқарилган сифатли маҳсулот номи',
          price: '89 000 сўм',
          priceNote: 'дан',
          footnote: 'Гурлан',
        ),
        width: 148,
        scale: 1.3,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('89 000 сўм'), findsOneWidget);
    });

    testWidgets('AvaChip — тор жойда тошмайди', (tester) async {
      await _pump(
        tester,
        const Row(
          children: [
            Flexible(child: AvaChip(label: 'Салонда: 1 аёл')),
            Flexible(child: AvaChip(label: 'Бугун 14:30')),
          ],
        ),
        width: 160,
        scale: 1.3,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Токенлардан фойдаланиш', () {
    testWidgets('AvaCard — усти ва контур токенлардан', (tester) async {
      await _pump(tester, const AvaCard(child: Text('x')));
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(AvaCard),
          matching: find.byType(Container),
        ).first,
      );
      final dec = container.decoration! as BoxDecoration;
      expect(dec.color, AvaColors.light.surface);
      expect(dec.border!.bottom.color, AvaColors.light.line);
    });

    testWidgets('AvaCard selected — контур бренд рангида', (tester) async {
      await _pump(tester, const AvaCard(selected: true, child: Text('x')));
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(AvaCard),
          matching: find.byType(Container),
        ).first,
      );
      final dec = container.decoration! as BoxDecoration;
      expect(dec.border!.bottom.color, AvaColors.light.brand);
    });

    testWidgets('AvaChip оҳанглари — ҳар бири ўз токенида', (tester) async {
      for (final (tone, bg) in <(AvaChipTone, Color)>[
        (AvaChipTone.neutral, AvaColors.light.chip),
        (AvaChipTone.brand, AvaColors.light.brandSoft),
        (AvaChipTone.ok, AvaColors.light.okSoft),
        (AvaChipTone.warn, AvaColors.light.warnSoft),
      ]) {
        await _pump(tester, AvaChip(label: 'x', tone: tone));
        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(AvaChip),
            matching: find.byType(Container),
          ).first,
        );
        final dec = container.decoration! as BoxDecoration;
        expect(dec.color, bg, reason: 'tone $tone');
      }
    });
  });

  group('AvaTileCard — 130% шрифтда тошмайди', () {
    // 2026-09-25, қурилмада: ён рўйхатнинг баландлиги қатъий 214 эди,
    // тизим шрифти 130% бўлганда нарх ва изоҳ карточкадан чиқиб,
    // кейинги бўлимнинг сарлавҳаси устига чизилган.
    for (final scale in [1.0, 1.3]) {
      testWidgets('карточка ажратилган баландликка сиғади (×$scale)',
          (tester) async {
        late double listHeight;
        await _pump(
          tester,
          Builder(
            builder: (context) {
              listHeight = avaTileListHeight(context);
              return SizedBox(
                height: listHeight,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: const [
                    AvaTileCard(
                      title: 'Жуда узун маҳсулот номи — икки қаторга сиғади',
                      price: 'дан 3 800 сўм',
                      priceNote: '1+ дона',
                      footnote: 'Sunlight',
                    ),
                  ],
                ),
              );
            },
          ),
          scale: scale,
        );

        expect(tester.takeException(), isNull);
        final cardHeight = tester.getSize(find.byType(AvaTileCard)).height;
        expect(
          cardHeight,
          lessThanOrEqualTo(listHeight),
          reason: 'карточка ($cardHeight) рўйхатдан ($listHeight) баланд',
        );
      });
    }

    testWidgets('баландлик шрифт билан ўсади', (tester) async {
      double at(BuildContext c) => avaTileListHeight(c);
      late double small;
      late double big;
      await _pump(tester, Builder(builder: (c) {
        small = at(c);
        return const SizedBox.shrink();
      }));
      await _pump(tester, Builder(builder: (c) {
        big = at(c);
        return const SizedBox.shrink();
      }), scale: 1.3);
      expect(big, greaterThan(small));
    });
  });
}
