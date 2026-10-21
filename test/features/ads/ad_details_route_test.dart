import 'package:ava_gurlan/features/ads/models/ad_model.dart';
import 'package:ava_gurlan/features/ads/screens/ad_details_route.dart';
import 'package:ava_gurlan/features/ads/screens/ad_details_screen.dart';
import 'package:ava_gurlan/features/ads/screens/ad_swipe_screen.dart';
import 'package:flutter_test/flutter_test.dart';

AdModel _ad(String id) => AdModel(
      id: id,
      ownerId: '998900000000',
      title: 'Эълон $id',
      titleLower: 'эълон $id',
      description: '',
      price: 1000,
      phone: '998900000000',
      sellerName: '',
      imageUrls: const [],
      status: 'active',
      views: 0,
    );

/// Эга талаби (2026-10-21): свайп эълонга ҚАЙСИ ЖОЙДАН кирилса ҳам ишласин —
/// рўйхат, бош саҳифа бўлими, «ўхшаш эълонлар». Учаласи шу ягона функциядан ўтади.
void main() {
  group('adDetailsFor', () {
    test('эълон рўйхатда — суриладиган экран, босилган ўрнидан бошланади', () {
      final list = [_ad('a'), _ad('b'), _ad('c')];
      final w = adDetailsFor(list[1], list);
      expect(w, isA<AdSwipeScreen>());
      final swipe = w as AdSwipeScreen;
      expect(swipe.initialIndex, 1);
      expect(swipe.ads.map((e) => e.id), ['a', 'b', 'c']);
    });

    test('биринчи ва охирги эълон ҳам тўғри ўрин олади', () {
      final list = [_ad('a'), _ad('b'), _ad('c')];
      expect((adDetailsFor(list.first, list) as AdSwipeScreen).initialIndex, 0);
      expect((adDetailsFor(list.last, list) as AdSwipeScreen).initialIndex, 2);
    });

    test('ID бўйича топилади (бошқа нусха объект бўлса ҳам)', () {
      final list = [_ad('a'), _ad('b')];
      final w = adDetailsFor(_ad('b'), list);
      expect((w as AdSwipeScreen).initialIndex, 1);
    });

    test('рўйхат бўш / эълон рўйхатда йўқ / битта эълон — одатдаги экран', () {
      expect(adDetailsFor(_ad('a'), const []), isA<AdDetailsScreen>());
      expect(adDetailsFor(_ad('x'), [_ad('a'), _ad('b')]), isA<AdDetailsScreen>());
      expect(adDetailsFor(_ad('a'), [_ad('a')]), isA<AdDetailsScreen>());
    });

    test('REGRESSION: бўш рўйхатда йиқилмайди', () {
      expect(() => adDetailsFor(_ad('a'), const []), returnsNormally);
    });
  });
}
