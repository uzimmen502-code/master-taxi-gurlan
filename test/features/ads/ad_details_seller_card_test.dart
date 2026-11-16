// Аралаш бозор эълони тафсилоти: сотувчи карточкасида ном такрорланмайди, «Ёзиш» қўнғироқдан тор,
// ўз эълонида «Ёзиш» йўқ (эга, 2026-11-01). Firebase'сиз: AdsRepository — fake.
import 'package:ava_gurlan/features/ads/models/ad_model.dart';
import 'package:ava_gurlan/features/ads/repositories/ads_repository.dart';
import 'package:ava_gurlan/features/ads/screens/ad_details_screen.dart';
import 'package:ava_gurlan/shared/widgets/seller_other_products_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../restaurants/restaurants_l10n_harness.dart';

class _FakeAds implements AdsRepository {
  @override
  Future<List<AdModel>> getSimilarAds({required AdModel current, int limit = 6, double minScore = 0.35}) async => const [];
  @override
  Future<void> incrementViews(String adId) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AdModel _ad({String sellerName = 'Сотувчи', String owner = '998901112233'}) => AdModel(
      id: 'a1',
      ownerId: owner,
      title: 'подсолнечное масло',
      titleLower: 'подсолнечное масло',
      description: 'тозаси бир литр',
      price: 20000,
      phone: owner,
      sellerName: sellerName,
      imageUrls: const [],
      status: 'active',
      views: 22,
    );

void main() {
  final d = JsonL10nDelegate();

  Future<void> pump(WidgetTester tester, AdModel ad, {String me = ''}) async {
    SharedPreferences.setMockInitialValues({if (me.isNotEmpty) 'user_phone': me});
    final prev = FlutterError.onError;
    FlutterError.onError = (e) {
      // Тест шрифти (Ahem) ва Firebase'сиз видео тугмаси — фақат шу экран тузилиши текширилади.
      final s = e.exceptionAsString();
      if (s.contains('overflowed by') || s.contains('No Firebase App')) return;
      prev?.call(e);
    };
    addTearDown(() => FlutterError.onError = prev);
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(Provider<AdsRepository>.value(
      value: _FakeAds(),
      child: l10nApp(delegate: d, home: AdDetailsScreen(ad: ad)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  // Эга 2026-11-16: ягона қатор «<Сотувчи> · Сотувчининг бошқа маҳсулотлари →» — фақат 1 тадан кўп фаол эълон бўлса.
  testWidgets('сотувчида 2 та фаол эълон — «<Сотувчи> · бошқа маҳсулотлари» қатори', (tester) async {
    SellerOtherProductsRow.debugSeed('ads:998901112233', true);
    addTearDown(SellerOtherProductsRow.debugReset);
    await pump(tester, _ad());
    expect(find.byKey(const ValueKey('seller_other_products_row')), findsOneWidget);
    expect(find.byKey(const ValueKey('ad_seller_all')), findsNothing, reason: 'эски карточка йўқ (иккита эмас)');
    // Навигация мақсади (SellerAdsScreen) — home_ui_batch тестида манбадан текширилади.
    expect(find.text('Сотувчи · seller_other_products').evaluate().isNotEmpty || find.textContaining('Сотувчи ·').evaluate().isNotEmpty, isTrue);
  });

  testWidgets('сотувчида 1 та эълон ёки текширув хатоси — қатор йўқ', (tester) async {
    SellerOtherProductsRow.debugSeed('ads:998901112233', false);
    addTearDown(SellerOtherProductsRow.debugReset);
    await pump(tester, _ad());
    expect(find.byKey(const ValueKey('seller_other_products_row')), findsNothing);
    SellerOtherProductsRow.debugReset();
    // Fake репозиторийда count йўқ → хато → қатор чиқмайди.
    await tester.pumpWidget(const SizedBox());
    await pump(tester, _ad());
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('seller_other_products_row')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Ёзиш» қўнғироқдан тор; ўз эълонида «Ёзиш» йўқ', (tester) async {
    await pump(tester, _ad(), me: '998905556677');
    final write = find.byKey(const ValueKey('ad_write_seller'));
    expect(write, findsOneWidget);
    expect(tester.getSize(write).width, lessThan(tester.getSize(find.byType(ElevatedButton)).width));

    await tester.pumpWidget(const SizedBox()); // янги экран — рақам қайта ўқилади
    await pump(tester, _ad(), me: '+998 90 111 22 33');
    expect(find.byKey(const ValueKey('ad_write_seller')), findsNothing);
  });
}
