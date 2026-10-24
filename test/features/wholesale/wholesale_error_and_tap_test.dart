import 'dart:async';

import 'package:ava_gurlan/core/theme/product_detail_dark.dart';
import 'package:ava_gurlan/features/wholesale/models/wholesale_product.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_stream_builder.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_tier_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('WholesaleStreamBuilder - xato "bo\'sh" holat emas (UI/UX audit 2026-10-24)', () {
    testWidgets('stream xato bersa builder CHAQIRILMAYDI, qayta urinish chiqadi',
        (tester) async {
      var builderCalls = 0;
      var retries = 0;
      await tester.pumpWidget(_host(
        WholesaleStreamBuilder<String?>(
          stream: Stream<String?>.error(StateError('permission-denied boom')),
          onRetry: () => retries++,
          builder: (_, __) {
            builderCalls++;
            return const Text('BUILDER');
          },
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(builderCalls, 0, reason: 'xatoda "sotuvchi yo\'q" shoxiga tushmasin');
      expect(find.text('BUILDER'), findsNothing);
      expect(find.byType(WholesaleLoadError), findsOneWidget);
      // Ichki exception matni foydalanuvchiga ko'rinmaydi (CLAUDE.md 25).
      expect(find.textContaining('boom'), findsNothing);
      expect(find.textContaining('StateError'), findsNothing);

      await tester.tap(find.byType(OutlinedButton));
      expect(retries, 1);
    });

    testWidgets('qayta urinish tugmasi 48 dp dan kichik emas', (tester) async {
      await tester.pumpWidget(_host(WholesaleLoadError(onRetry: () {})));
      final size = tester.getSize(find.byType(OutlinedButton));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    });

    testWidgets('hujjat yo\'q (null) - xato emas, builder null bilan chaqiriladi',
        (tester) async {
      Object? seen = 'unset';
      await tester.pumpWidget(_host(
        WholesaleStreamBuilder<String?>(
          stream: Stream<String?>.value(null),
          onRetry: () {},
          builder: (_, data) {
            seen = data;
            return const Text('REGISTER');
          },
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byType(WholesaleLoadError), findsNothing);
      expect(find.text('REGISTER'), findsOneWidget);
      expect(seen, isNull);
    });

    testWidgets('birinchi ma\'lumot kelguncha spinner', (tester) async {
      final ctrl = StreamController<String?>();
      addTearDown(ctrl.close);
      await tester.pumpWidget(_host(
        WholesaleStreamBuilder<String?>(
          stream: ctrl.stream,
          onRetry: () {},
          builder: (_, __) => const Text('DATA'),
        ),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('DATA'), findsNothing);

      ctrl.add('x');
      await tester.pump();
      expect(find.text('DATA'), findsOneWidget);
    });
  });

  group('Tier picker - touch target >= 48 dp (UI/UX audit 2026-10-24)', () {
    WholesaleProduct product() => WholesaleProduct(
          id: 'p',
          sellerId: 's',
          sellerCompanyName: 'Firma',
          title: 'Tomato',
          titleLower: 'tomato',
          description: '',
          unit: 'kg',
          priceTiers: const [
            PriceTier(minQty: 1, price: 14000),
            PriceTier(minQty: 10, price: 12000),
            PriceTier(minQty: 50, price: 10500),
          ],
        );

    Future<void> pump(WidgetTester tester) async {
      final p = product();
      await tester.pumpWidget(MaterialApp(
        home: ProductDetailDark(
          child: Scaffold(
            body: SingleChildScrollView(
              child: WholesaleTierPicker(
                product: p,
                qty: p.moq,
                onQtyChanged: (_) {},
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('+ / - tugmalari va miqdor maydoni', (tester) async {
      await pump(tester);
      for (final icon in [Icons.add_rounded, Icons.remove_rounded]) {
        final box = find.ancestor(
          of: find.byIcon(icon),
          matching: find.byType(SizedBox),
        ).first;
        final s = tester.getSize(box);
        expect(s.width, greaterThanOrEqualTo(48), reason: '$icon width');
        expect(s.height, greaterThanOrEqualTo(48), reason: '$icon height');
      }
      final field = tester.getSize(find.byType(TextField));
      expect(field.height, greaterThanOrEqualTo(48));
    });

    testWidgets('"miqdorni o\'rnat" havolasi', (tester) async {
      await pump(tester);
      // `tr` delegatsiz testda kalitning o'zini qaytaradi.
      final link = find.ancestor(
        of: find.text('wholesale_set_qty'),
        matching: find.byType(InkWell),
      );
      expect(link, findsOneWidget);
      expect(tester.getSize(link).height, greaterThanOrEqualTo(48));
    });
  });
}
