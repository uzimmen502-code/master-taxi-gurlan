// Аралаш бозор эълони тафсилоти: сотувчи карточкасида ном такрорланмайди, «Ёзиш» қўнғироқдан тор,
// ўз эълонида «Ёзиш» йўқ (эга, 2026-11-01). Firebase'сиз: AdsRepository — fake.
import 'package:ava_gurlan/features/ads/models/ad_model.dart';
import 'package:ava_gurlan/features/ads/repositories/ads_repository.dart';
import 'package:ava_gurlan/features/ads/screens/ad_details_screen.dart';
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

  testWidgets('сотувчи карточкаси: битта қатор «Сотувчининг барча маҳсулотлари», ном такрорланмайди', (tester) async {
    await pump(tester, _ad());
    expect(find.byKey(const ValueKey('ad_seller_all')), findsOneWidget);
    // «Сотувчи» номи фақат сарлавҳа остида — бир марта.
    expect(find.text('Сотувчи'), findsOneWidget);
    // Ихчам: майдон баландлиги ≈ шрифт баландлиги (эга, 2026-11-01).
    final box = tester.getSize(find.byKey(const ValueKey('ad_seller_all_box'))).height;
    expect(box, lessThanOrEqualTo(26));
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
