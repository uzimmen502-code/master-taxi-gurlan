import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/my_shop/pending_shop_link.dart';
import 'package:ava_gurlan/features/my_shop/screens/my_shop_screen.dart';
import 'package:ava_gurlan/features/my_shop/widgets/shop_link_sheet.dart';
import 'package:ava_gurlan/features/tv_market/screens/tv_shop_public_screen.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// 5-босқич (эга қарори 2026-10-25): дўконнинг доимий ҳаволаси ва QR.
const _url = 'https://master-taxi-gurlan.web.app/s/AbCdEfGh23';

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(480 * 2, 1400 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: home));
  await tester.pumpAndSettle();
}

void main() {
  group('PendingShopLink (веб: /?shop=<id>)', () {
    test('фақат тўғри 10 белгили ID ушланади; бир марта олинади', () {
      PendingShopLink.captureFromUrl(Uri.parse('https://x.app/?shop=AbCdEfGh23'));
      expect(PendingShopLink.take(), 'AbCdEfGh23');
      expect(PendingShopLink.take(), isNull, reason: 'қайта очилмайди');
      for (final bad in ['https://x.app/?shop=998901111111', 'https://x.app/?shop=../x', 'https://x.app/']) {
        PendingShopLink.captureFromUrl(Uri.parse(bad));
        expect(PendingShopLink.take(), isNull, reason: bad);
      }
    });

    testWidgets('ҳавола ечилса — айнан шу дўкон ва йўналиш; мавжуд бўлмаса — «вақтинча мавжуд эмас»', (tester) async {
      Widget? pushed;
      late BuildContext ctx;
      await _pump(tester, Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      PendingShopLink.captureFromUrl(Uri.parse('https://x.app/?shop=AbCdEfGh23'));
      await PendingShopLink.openIfAny(ctx,
          resolve: (_) async => (ownerPhone: '998901111111', businessId: 'm1'), push: (w) => pushed = w);
      expect(pushed, isA<TvShopPublicScreen>());
      expect([(pushed! as TvShopPublicScreen).ownerPhone, (pushed! as TvShopPublicScreen).businessId], ['998901111111', 'm1']);

      PendingShopLink.captureFromUrl(Uri.parse('https://x.app/?shop=ZZZZZZZZZZ'));
      pushed = null;
      await PendingShopLink.openIfAny(ctx, resolve: (_) async => null, push: (w) => pushed = w);
      await tester.pump();
      expect(pushed, isNull);
      expect(find.text('shop_unavailable'), findsOneWidget);
    });
  });

  group('ShopLinkSheet', () {
    testWidgets('ҳавола, QR (манба белгиси qr), тугмалар; телефон йўқ', (tester) async {
      await _pump(tester, Scaffold(body: ShopLinkSheet(title: 'Сидабилла', loadLink: ({String businessId = ''}) async => _url)));
      expect(find.text(_url), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(shopLinkWithSource(_url, 'qr'), '$_url?src=qr');
      expect(shopLinkWithSource(_url, 'link'), '$_url?src=link');
      for (final k in ['shop_link_copy', 'shop_link_share', 'shop_link_share_qr']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
    });

    testWidgets('блокланган дўкон — тушунарли матн, QR йўқ', (tester) async {
      await _pump(tester, Scaffold(body: ShopLinkSheet(
        title: 'С',
        loadLink: ({String businessId = ''}) async =>
            throw FirebaseFunctionsException(message: 'x', code: 'failed-precondition', details: {'code': 'SHOP_BLOCKED'}),
      )));
      expect(find.text('bizprod_blocked_banner'), findsOneWidget);
      expect(find.byKey(const ValueKey('shop_link_qr')), findsNothing);
    });
  });

  group('MyShopScreen: QR тугмалари', () {
    testWidgets('асосий дўкон ва йўналиш — ҳар бирининг ўз ҳаволаси', (tester) async {
      final asked = <String>[];
      await _pump(tester, MyShopScreen(
        phone: '998901111111',
        businesses: Stream.value(const [
          Business(id: 'm1', ownerId: '998901111111', name: 'Кийим', category: BusinessCategory.retail, phone: '1', lat: 41, lng: 60),
        ]),
        loadMainName: () async => 'Сидабилла',
        loadLink: ({String businessId = ''}) async {
          asked.add(businessId);
          return _url;
        },
      ));
      await tester.tap(find.byKey(const ValueKey('my_shop_link_main')));
      await tester.pumpAndSettle();
      expect(find.text(_url), findsOneWidget);
      Navigator.of(tester.element(find.text(_url))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('my_shop_link_m1')));
      await tester.pumpAndSettle();
      expect(asked, ['', 'm1']);
    });
  });
}
