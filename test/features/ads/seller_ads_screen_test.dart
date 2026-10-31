import 'package:ava_gurlan/features/ads/models/ad_model.dart';
import 'package:ava_gurlan/features/ads/repositories/ads_repository.dart';
import 'package:ava_gurlan/features/ads/screens/seller_ads_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../restaurants/restaurants_l10n_harness.dart';

/// «Сотувчининг барча маҳсулотлари» (Аҳоли бозори, эга 2026-11-01).
class _FakeAds implements AdsRepository {
  _FakeAds(this.stream);
  final Stream<List<AdModel>> stream;
  String? askedOwner;

  @override
  Stream<List<AdModel>> watchSellerActiveAds(String ownerId, {int limit = AdsRepository.feedLimit}) {
    askedOwner = ownerId;
    return stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _l10n = JsonL10nDelegate('uz_Cyrl');

AdModel _ad(String id, String title) => AdModel.fromMap(id, {
      'type': AdModel.typeKey,
      'title': title,
      'price': 1000,
      'status': 'active',
      'ownerId': '998901112233',
      'imageUrls': const <String>[],
    });

void main() {
  testWidgets('сотувчининг фаол эълонлари рўйхати чиқади', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // Тест шрифти (FlutterTest) ҳақиқийдан катта: мавжуд [AdCard] 1 px тошади — фақат шу хабар эътиборсиз.
    final prev = FlutterError.onError;
    FlutterError.onError = (d) { if (!d.toString().contains('overflowed')) prev?.call(d); };
    addTearDown(() => FlutterError.onError = prev);
    final repo = _FakeAds(Stream.value([_ad('a1', 'Мол'), _ad('a2', 'Қўй')]));
    await tester.pumpWidget(l10nApp(
      delegate: _l10n,
      home: SellerAdsScreen(ownerId: '998901112233', sellerName: 'Акмал', repository: repo),
    ));
    await tester.pumpAndSettle();
    expect(repo.askedOwner, '998901112233');
    expect(find.text('Сотувчининг барча маҳсулотлари'), findsOneWidget);
    expect(find.text('Акмал'), findsOneWidget);
    expect(find.text('Мол'), findsOneWidget);
    expect(find.text('Қўй'), findsOneWidget);
  });

  testWidgets('бошқа фаол эълон йўқ — тушунарли матн', (tester) async {
    final repo = _FakeAds(Stream.value(const []));
    await tester.pumpWidget(l10nApp(
      delegate: _l10n,
      home: SellerAdsScreen(ownerId: '998901112233', sellerName: '', repository: repo),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Бу сотувчининг бошқа фаол эълонлари йўқ'), findsOneWidget);
  });
}
