import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:ava_gurlan/features/tv_market/services/tv_publish_rules.dart';
import 'package:flutter_test/flutter_test.dart';

TvClip _clip(String id, {DateTime? createdAt}) => TvClip(
      id: id,
      videoUrl: 'https://x/$id.mp4',
      posterUrl: '',
      title: id,
      price: 0,
      districtId: 'gurlan',
      districtLabel: 'Гурлан',
      ownerPhone: '998901234567',
      ownerName: 'Али',
      category: 'product',
      createdAt: createdAt,
    );

void main() {
  group('TvPublishRules.shopMode — дўкони бор одам боғланган видео жойлай олади', () {
    bool mode({
      bool isAd = false,
      bool isNews = false,
      bool openShop = false,
      String attach = '',
      bool hide = false,
    }) =>
        TvPublishRules.shopMode(
          isAd: isAd,
          isNews: isNews,
          openShop: openShop,
          attachItemId: attach,
          hideShopOption: hide,
        );

    test('REGRESSION: дўкон блоки яширин (ресторан видеоси) + _openShop=true → режим ЎЧИҚ', () {
      expect(mode(openShop: true, hide: true), isFalse);
    });

    test('яширин + бириктирилган товар → барибир ўчиқ', () {
      expect(mode(attach: 'item1', hide: true), isFalse);
    });

    test('оддий AVAGram: дўкон ёқилган → режим ёқиқ (ўзгармади)', () {
      expect(mode(openShop: true), isTrue);
      expect(mode(attach: 'item1'), isTrue);
    });

    test('дўкон ёқилмаган → ўчиқ', () {
      expect(mode(), isFalse);
    });

    test('реклама ва янгиликда дўкон режими йўқ', () {
      expect(mode(isAd: true, openShop: true), isFalse);
      expect(mode(isNews: true, openShop: true), isFalse);
    });
  });

  group('TvPublishRules.showCategorySelector / organicCategory', () {
    test('боғланган видеода тур сегменти кўринмайди', () {
      expect(TvPublishRules.showCategorySelector(categoryLocked: false, organicOnly: true), isFalse);
    });

    test('оддий жойлашда кўринади', () {
      expect(TvPublishRules.showCategorySelector(categoryLocked: false, organicOnly: false), isTrue);
    });

    test('ad/news таҳририда қулф — кўринмайди', () {
      expect(TvPublishRules.showCategorySelector(categoryLocked: true, organicOnly: false), isFalse);
    });

    test('тур linkKind дан: ресторан/бозор/эълон → product, хизмат → service', () {
      expect(TvPublishRules.organicCategory('restaurant'), 'product');
      expect(TvPublishRules.organicCategory('market_ad'), 'product');
      expect(TvPublishRules.organicCategory('ad'), 'product');
      expect(TvPublishRules.organicCategory('wholesale_product'), 'product');
      expect(TvPublishRules.organicCategory('service'), 'service');
    });
  });

  group('tvClipsNewestFirst — бир linkId да бир нечта клип', () {
    test('янгиси биринчи, createdAt йўқлари охирида', () {
      final out = tvClipsNewestFirst([
        _clip('old', createdAt: DateTime(2026, 10, 1)),
        _clip('none'),
        _clip('new', createdAt: DateTime(2026, 10, 17)),
      ]);
      expect(out.map((c) => c.id), ['new', 'old', 'none']);
    });

    test('кириш рўйхати ўзгармайди, бўш рўйхат йиқилмайди', () {
      final input = [_clip('a', createdAt: DateTime(2026, 1, 1)), _clip('b', createdAt: DateTime(2026, 2, 1))];
      tvClipsNewestFirst(input);
      expect(input.map((c) => c.id), ['a', 'b']);
      expect(tvClipsNewestFirst(const []), isEmpty);
    });
  });
}
