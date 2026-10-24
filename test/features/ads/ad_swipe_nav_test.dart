import 'package:ava_gurlan/core/widgets/edge_swipe_pager.dart';
import 'package:ava_gurlan/features/ads/models/ad_model.dart';
import 'package:ava_gurlan/features/ads/screens/ad_swipe_screen.dart';
import 'package:ava_gurlan/features/ads/widgets/ad_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Аҳоли бозори UI/UX аудити (2026-10-24, 1-банд): свайп ягона йўл бўлмасин —
/// олдинги/кейинги эълонга тугма билан ўтиш бор.
Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('AdSwipeNav', () {
    testWidgets('биринчи эълон: «олдинги» ўчиқ, «кейинги» ишлайди',
        (t) async {
      final steps = <int>[];
      await t.pumpWidget(_host(AdSwipeNav(index: 0, count: 3, onStep: steps.add)));
      expect(find.text('1 / 3'), findsOneWidget);

      final prev = t.widget<IconButton>(find.byKey(const ValueKey('ad-swipe-prev')));
      final next = t.widget<IconButton>(find.byKey(const ValueKey('ad-swipe-next')));
      expect(prev.onPressed, isNull);
      expect(next.onPressed, isNotNull);

      await t.tap(find.byKey(const ValueKey('ad-swipe-next')));
      expect(steps, [1]);
    });

    testWidgets('охирги эълон: «кейинги» ўчиқ, «олдинги» ишлайди', (t) async {
      final steps = <int>[];
      await t.pumpWidget(_host(AdSwipeNav(index: 2, count: 3, onStep: steps.add)));
      expect(find.text('3 / 3'), findsOneWidget);

      final next = t.widget<IconButton>(find.byKey(const ValueKey('ad-swipe-next')));
      expect(next.onPressed, isNull);

      await t.tap(find.byKey(const ValueKey('ad-swipe-prev')));
      expect(steps, [-1]);
    });

    testWidgets('ўртада иккиси ҳам ишлайди; тугмалар ≥48 dp', (t) async {
      await t.pumpWidget(_host(AdSwipeNav(index: 1, count: 3, onStep: (_) {})));
      for (final k in const ['ad-swipe-prev', 'ad-swipe-next']) {
        final b = t.widget<IconButton>(find.byKey(ValueKey(k)));
        expect(b.onPressed, isNotNull, reason: k);
        final size = t.getSize(find.byKey(ValueKey(k)));
        expect(size.width, greaterThanOrEqualTo(48), reason: k);
        expect(size.height, greaterThanOrEqualTo(48), reason: k);
      }
    });

    testWidgets('тугмаларда экран ўқувчи номи (tooltip) бор', (t) async {
      await t.pumpWidget(_host(AdSwipeNav(index: 1, count: 3, onStep: (_) {})));
      // Тест'да локализация йўқ — калитнинг ўзи қайтади. Tooltip =
      // тугманинг экран ўқувчидаги номи.
      expect(find.byTooltip('ad_swipe_prev'), findsOneWidget);
      expect(find.byTooltip('ad_swipe_next'), findsOneWidget);
    });
  });

  group('EdgeSwipePager ташқи controller', () {
    testWidgets('тугма (controller) билан ўтилади ва controller ёпилмайди',
        (t) async {
      final ctrl = PageController();
      final changed = <int>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EdgeSwipePager(
            itemCount: 3,
            controller: ctrl,
            onPageChanged: changed.add,
            itemBuilder: (_, i) => ListView(
              physics: kEdgeSwipePhysics,
              children: [SizedBox(height: 200, child: Text('page $i'))],
            ),
          ),
        ),
      ));
      expect(find.text('page 0'), findsOneWidget);

      // `await` ЙЎҚ: анимация кадр берилганда тугайди (fake async).
      ctrl.animateToPage(1,
          duration: const Duration(milliseconds: 100), curve: Curves.linear);
      await t.pumpAndSettle();
      expect(find.text('page 1'), findsOneWidget);
      expect(changed, [1]);

      // Пейджер олиб ташланса ҳам ташқи controller яшайди (ёпилмайди).
      await t.pumpWidget(const SizedBox.shrink());
      expect(() => ctrl.dispose(), returnsNormally);
    });
  });

  group('AdCard — экран ўқувчи', () {
    testWidgets('карта битта тугма: ном ва нарх биргаликда ўқилади', (t) async {
      final h = t.ensureSemantics();
      final ad = AdModel(
        id: 'a1',
        ownerId: '998900000000',
        title: 'Холодильник',
        titleLower: 'холодильник',
        description: '',
        price: 2500000,
        phone: '998900000000',
        sellerName: '',
        imageUrls: const [],
        status: 'active',
        views: 0,
      );
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: SizedBox(width: 180, height: 260, child: AdCard(ad: ad))),
      ));
      final node = t.getSemantics(find.byType(InkWell));
      expect(node.label, contains('Холодильник'));
      expect(node.label, contains('2'));
      h.dispose();
    });
  });
}
